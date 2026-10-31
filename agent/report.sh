#!/bin/bash
# report.sh - monitor.log 를 분석해 CPU/MEM/DISK 의 평균·최대·최소와 샘플 수를 출력한다(보너스 1).
#
#   report.sh                                   전체 구간
#   report.sh "2026-09-15 13:00:00" "2026-09-15 14:00:00"   시작~종료 구간만
#
# 로그 시각은 "YYYY-MM-DD HH:MM:SS" 고정 폭이라 문자열 비교가 곧 시간 비교다.

PATH=/usr/local/bin:/usr/bin:/bin
if [ -z "${AGENT_LOG_DIR:-}" ] && [ -r /etc/profile.d/agent-app.sh ]; then
    . /etc/profile.d/agent-app.sh
fi
LOG_FILE=${MONITOR_LOG:-${AGENT_LOG_DIR:-/var/log/agent-app}/monitor.log}
FROM=${1:-0000-00-00 00:00:00}
TO=${2:-9999-99-99 99:99:99}

if [ ! -r "$LOG_FILE" ]; then
    echo "[ERROR] 로그를 읽을 수 없다: $LOG_FILE" >&2
    exit 1
fi

awk -v from="$FROM" -v to="$TO" '
function val(key, v) { v = $0; sub("^.*" key ":", "", v); sub("%.*$", "", v); return v + 0 }
function track(k, v, ts) {
    sum[k] += v
    if (!(k in max) || v > max[k]) { max[k] = v; maxt[k] = ts }
    if (!(k in min) || v < min[k]) { min[k] = v; mint[k] = ts }
}
/^\[[0-9-]+ [0-9:]+\] PID:/ {
    ts = substr($0, 2, 19)
    if (ts < from || ts > to) next
    n++
    if (n == 1) first = ts
    last = ts
    track("CPU", val("CPU"), ts); track("MEM", val("MEM"), ts); track("DISK", val("DISK_USED"), ts)
}
END {
    print "  ====== STATISTICS REPORT ======"
    if (n == 0) { print "  [INFO] 해당 구간에 샘플이 없다."; exit }
    printf "  Range : %s ~ %s\n", first, last
    split("CPU Memory Disk", label, " "); split("CPU MEM DISK", key, " ")
    for (i = 1; i <= 3; i++) {
        k = key[i]
        printf "  [%s]\n", label[i]
        printf "    Average : %.1f%%\n", sum[k] / n
        printf "    Maximum : %.1f%% at %s\n", max[k], maxt[k]
        printf "    Minimum : %.1f%% at %s\n", min[k], mint[k]
    }
    print "  [Samples]"
    printf "    Data Points: %d samples\n", n
}' "$LOG_FILE"
