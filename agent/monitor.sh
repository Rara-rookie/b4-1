#!/bin/bash
# monitor.sh - agent-app 헬스체크, 자원 수집, 로그 기록
#
# 위치  : $AGENT_HOME/bin/monitor.sh  (소유 agent-dev, 그룹 agent-core, 권한 750)
# 실행  : agent-admin 의 crontab 으로 매분
# 종료  : 0 = 정상(경고 포함), 1 = 헬스체크 실패(프로세스 없음 또는 포트 미리슨)
#
# 점검용 덮어쓰기(운영에서는 쓰지 않는다)
#   MONITOR_PROCESS   확인할 프로세스 이름      기본 agent-app
#   MONITOR_PORT      확인할 포트               기본 $AGENT_PORT(15034)
#   MONITOR_LOG       로그 파일                 기본 $AGENT_LOG_DIR/monitor.log
#   MONITOR_MAX_BYTES 회전 기준 크기(바이트)    기본 10485760 (10MB)
#   MONITOR_KEEP      보관 파일 수(현재 포함)   기본 10

# cron 은 PATH 가 짧고 로그인 환경변수도 없다. 둘 다 스스로 채운다.
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
umask 007
if [ -z "${AGENT_HOME:-}" ] && [ -r /etc/profile.d/agent-app.sh ]; then
    . /etc/profile.d/agent-app.sh
fi

PROCESS_NAME=${MONITOR_PROCESS:-agent-app}
PORT=${MONITOR_PORT:-${AGENT_PORT:-15034}}
LOG_DIR=${AGENT_LOG_DIR:-/var/log/agent-app}
LOG_FILE=${MONITOR_LOG:-$LOG_DIR/monitor.log}
MAX_BYTES=${MONITOR_MAX_BYTES:-10485760}
KEEP_FILES=${MONITOR_KEEP:-10}

CPU_LIMIT=20
MEM_LIMIT=10
DISK_LIMIT=80

now() { date '+%Y-%m-%d %H:%M:%S'; }

# 부동소수 비교: a > b 이면 참
gt() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a > b) }'; }

# /proc/stat 을 1초 간격으로 두 번 읽어 그 사이 idle 이 아닌 시간의 비율을 구한다.
cpu_usage() {
    local a b
    read -r _ a1 a2 a3 a4 a5 a6 a7 a8 _ < /proc/stat
    sleep 1
    read -r _ b1 b2 b3 b4 b5 b6 b7 b8 _ < /proc/stat
    local idle=$(( (b4 + b5) - (a4 + a5) ))
    local total=$(( (b1 + b2 + b3 + b4 + b5 + b6 + b7 + b8) - (a1 + a2 + a3 + a4 + a5 + a6 + a7 + a8) ))
    awk -v i="$idle" -v t="$total" 'BEGIN { if (t <= 0) print "0.0"; else printf "%.1f", (t - i) * 100 / t }'
}

# 캐시처럼 회수 가능한 메모리는 사용량에서 뺀다(MemAvailable 기준).
mem_usage() {
    awk '/^MemTotal:/ { t = $2 } /^MemAvailable:/ { a = $2 }
         END { if (t > 0) printf "%.1f", (t - a) * 100 / t; else print "0.0" }' /proc/meminfo
}

disk_usage() {
    df -P / | awk 'NR == 2 { gsub("%", "", $5); print $5 }'
}

# ufw status 는 root 권한이 필요하다. agent-admin 에게는 sudoers 로 이 명령 하나만 허용했다.
# sudo 가 안 되는 계정(agent-dev 등)은 설정 파일의 활성화 여부로 대신 판단한다.
firewall_state() {
    local out
    if out=$(sudo -n /usr/sbin/ufw status 2>/dev/null); then
        case "$out" in *"Status: active"*) echo active ;; *) echo inactive ;; esac
    elif grep -qs '^ENABLED=yes' /etc/ufw/ufw.conf; then
        echo "active (ufw.conf)"
    else
        echo inactive
    fi
}

# monitor.log 가 한도를 넘으면 monitor.log -> .1 -> .2 ... 로 밀고 가장 오래된 것을 지운다.
rotate_log() {
    [ -f "$LOG_FILE" ] || return 0
    local size
    size=$(stat -c %s "$LOG_FILE")
    [ "$size" -lt "$MAX_BYTES" ] && return 0
    local i=$(( KEEP_FILES - 1 ))
    rm -f "$LOG_FILE.$i"
    while [ "$i" -gt 1 ]; do
        [ -f "$LOG_FILE.$(( i - 1 ))" ] && mv -f "$LOG_FILE.$(( i - 1 ))" "$LOG_FILE.$i"
        i=$(( i - 1 ))
    done
    mv -f "$LOG_FILE" "$LOG_FILE.1"
    echo "[INFO] Log rotated: $LOG_FILE (${size} bytes >= ${MAX_BYTES})"
}

print_statistics() {
    [ -s "$LOG_FILE" ] || return 0
    awk '
    function stat(name, i, v) {
        v = $0; sub("^.*" name ":", "", v); sub("%.*$", "", v); return v + 0
    }
    /^\[[0-9-]+ [0-9:]+\] PID:/ {
        ts = substr($0, 2, 19); n++
        c = stat("CPU"); m = stat("MEM")
        cs += c; ms += m
        if (n == 1 || c > cmax) { cmax = c; cmaxt = ts }
        if (n == 1 || c < cmin) { cmin = c; cmint = ts }
        if (n == 1 || m > mmax) { mmax = m; mmaxt = ts }
        if (n == 1 || m < mmin) { mmin = m; mmint = ts }
    }
    END {
        if (n == 0) exit
        print "====== STATISTICS REPORT ======"
        print "[CPU]"
        printf "Average : %.1f%%\nMaximum : %.1f%% at %s\nMinimum : %.1f%% at %s\n", cs / n, cmax, cmaxt, cmin, cmint
        print "[Memory]"
        printf "Average : %.1f%%\nMaximum : %.1f%% at %s\nMinimum : %.1f%% at %s\n", ms / n, mmax, mmaxt, mmin, mmint
        print "[Samples]"
        printf "Data Points: %d samples\n", n
    }' "$LOG_FILE"
}

mkdir -p "$(dirname "$LOG_FILE")"
# cron 이 이전 실행과 겹치면 로그가 섞인다. 이미 돌고 있으면 이번 회차는 건너뛴다.
exec 9>>"$(dirname "$LOG_FILE")/.monitor.lock"
if ! flock -n 9; then
    echo "[INFO] 이전 monitor.sh 가 아직 실행 중이다. 이번 회차를 건너뛴다."
    exit 0
fi

echo "====== SYSTEM MONITOR RESULT ======"
echo
echo "[HEALTH CHECK]"
# PyInstaller 로 만든 앱은 부트로더와 실제 워커 두 프로세스가 같은 이름으로 뜬다. 가장 최근(워커)을 쓴다.
PID=$(pgrep -n -x "$PROCESS_NAME")
if [ -z "$PID" ]; then
    echo "Checking process '$PROCESS_NAME'... [FAIL]"
    rotate_log
    echo "[$(now)] [ERROR] process '$PROCESS_NAME' is not running" >> "$LOG_FILE"
    exit 1
fi
echo "Checking process '$PROCESS_NAME'... [OK] (PID: $PID)"

if [ -z "$(ss -Hltn "sport = :$PORT")" ]; then
    echo "Checking port $PORT... [FAIL]"
    rotate_log
    echo "[$(now)] [ERROR] port $PORT is not listening (PID:$PID)" >> "$LOG_FILE"
    exit 1
fi
echo "Checking port $PORT... [OK]"

echo
echo "[STATUS CHECK]"
FW=$(firewall_state)
if [ "${FW%% *}" = active ]; then
    echo "Firewall (ufw) : $FW"
else
    echo "Firewall (ufw) : $FW"
    FW_WARN="[WARNING] Firewall is not active"
fi

CPU=$(cpu_usage)
MEM=$(mem_usage)
DISK=$(disk_usage)

echo
echo "[RESOURCE MONITORING]"
echo "CPU Usage : ${CPU}%"
echo "MEM Usage : ${MEM}%"
echo "DISK Used : ${DISK}%"
echo

[ -n "${FW_WARN:-}" ] && echo "$FW_WARN"
gt "$CPU" "$CPU_LIMIT"   && echo "[WARNING] CPU threshold exceeded (${CPU}% > ${CPU_LIMIT}%)"
gt "$MEM" "$MEM_LIMIT"   && echo "[WARNING] MEM threshold exceeded (${MEM}% > ${MEM_LIMIT}%)"
gt "$DISK" "$DISK_LIMIT" && echo "[WARNING] DISK threshold exceeded (${DISK}% > ${DISK_LIMIT}%)"

rotate_log
echo "[$(now)] PID:$PID CPU:${CPU}% MEM:${MEM}% DISK_USED:${DISK}%" >> "$LOG_FILE"

echo
print_statistics
echo
echo "[INFO] Log appended: $LOG_FILE"
exit 0
