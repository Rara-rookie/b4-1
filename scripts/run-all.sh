#!/bin/bash
# 컨테이너 안에서 1~7단계를 차례로 실행하고, 과제의 필수 증거 체크리스트를 판정한다.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib.sh"

rm -f "$EVIDENCE_DIR"/*.log
for step in step1-ssh step2-firewall step3-accounts step4-app step5-monitor step6-cron step7-bonus; do
    echo
    echo "################ $step ################"
    bash "$HERE/$step.sh"
done

step_begin 00-checklist "필수 증거 체크리스트 판정(실제 상태를 다시 조회해 판정한다)"
check() {
    local label=$1 cmd=$2
    if bash -c "$cmd" >/dev/null 2>&1; then
        echo "[PASS] $label" | tee -a "$STEP_LOG"
    else
        echo "[FAIL] $label" | tee -a "$STEP_LOG"
    fi
}
check "SSH 포트 20022 리슨, PermitRootLogin no" \
      "sshd -T | grep -qx 'port 20022' && sshd -T | grep -qx 'permitrootlogin no' && ss -tln | grep -q ':20022 '"
check "root SSH 접속 거부 기록" "grep -q 'ROOT LOGIN REFUSED' /var/log/sshd_auth.log"
check "UFW 활성, 허용 규칙은 20022/tcp·15034/tcp 뿐" \
      "ufw status | grep -q 'Status: active' && [ \"\$(ufw status | grep -c 'ALLOW')\" -eq 4 ] && ! ufw status | grep ALLOW | grep -vqE '^(20022|15034)/tcp'"
check "계정 3개와 그룹 소속" \
      "id -nG agent-admin | grep -qw agent-core && id -nG agent-dev | grep -qw agent-core && id -nG agent-test | grep -qw agent-common && ! id -nG agent-test | grep -qw agent-core"
check "upload_files=agent-common rwx, api_keys·로그=agent-core rwx" \
      "getfacl -p $AGENT_UPLOAD_DIR | grep -q '^group:agent-common:rwx' && getfacl -p $AGENT_KEY_PATH | grep -q '^group:agent-core:rwx' && getfacl -p $AGENT_LOG_DIR | grep -q '^group:agent-core:rwx'"
check "agent-test 는 api_keys 접근 불가" "! su - agent-test -c 'ls $AGENT_KEY_PATH'"
check "Boot Sequence 5단계 [OK] 와 Agent READY" \
      "[ \"\$(grep -c '\[OK\]' $AGENT_HOME/agent-app.out)\" -ge 5 ] && grep -q 'Agent READY' $AGENT_HOME/agent-app.out"
check "앱이 0.0.0.0:15034 LISTEN, 실행 계정 agent-admin" \
      "ss -tln | grep -q '0.0.0.0:15034' && [ \"\$(ps -o user= -p \$(pgrep -n -x agent-app))\" = agent-admin ]"
check "monitor.sh 위치/소유/권한" "[ \"\$(stat -c '%U:%G %a' $AGENT_HOME/bin/monitor.sh)\" = 'agent-dev:agent-core 750' ]"
check "monitor.log 형식" "grep -qE '^\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:]{8}\] PID:[0-9]+ CPU:[0-9.]+% MEM:[0-9.]+% DISK_USED:[0-9]+%$' $AGENT_LOG_DIR/monitor.log"
check "agent-admin crontab 매분 등록" "crontab -l -u agent-admin | grep -q '^\* \* \* \* \* .*monitor.sh'"
check "cron 자동 실행으로 로그 증가" "grep -q '^# cron 이 추가한 줄: [2-9]' $EVIDENCE_DIR/06-cron.log"
run "tail -5 $AGENT_LOG_DIR/monitor.log"
