#!/bin/bash
# 4. monitor.sh 를 정책대로 배치하고 정상·실패·경고 경로를 모두 실행해 본다.
set -u
. "$(dirname "$0")/lib.sh"
step_begin 05-monitor "monitor.sh 배치(agent-dev:agent-core 750)와 실행 결과"

section "배치: 작성자 agent-dev 가 설치"
for f in monitor.sh report.sh log-retention.sh; do
    install -m 644 "$B41_ROOT/agent/$f" "/tmp/$f"
done
run_as agent-dev 'for f in monitor.sh report.sh log-retention.sh; do install -m 750 -g agent-core /tmp/$f $AGENT_HOME/bin/$f; done'
run "stat -c '%U:%G %a %n' $AGENT_HOME/bin/*.sh"

section "sudoers: agent-admin 에게 방화벽 상태 조회 한 가지만 허용"
printf 'agent-admin ALL=(root) NOPASSWD: /usr/sbin/ufw status\n' > /etc/sudoers.d/agent-monitor
chmod 440 /etc/sudoers.d/agent-monitor
run "cat /etc/sudoers.d/agent-monitor && visudo -cf /etc/sudoers.d/agent-monitor"
run_as agent-admin "sudo -n -l"

section "정상 실행(cron 실행 계정 agent-admin)"
run_as agent-admin '$AGENT_HOME/bin/monitor.sh; echo "exit=$?"'
run_as agent-admin '$AGENT_HOME/bin/monitor.sh > /dev/null; $AGENT_HOME/bin/monitor.sh > /dev/null; tail -3 $AGENT_LOG_DIR/monitor.log'

section "권한 없는 계정(agent-test)은 실행할 수 없다"
run_as agent-test '$AGENT_HOME/bin/monitor.sh; echo "exit=$?"'

section "Health Check 실패 시 exit 1"
run_as agent-admin 'MONITOR_PROCESS=no-such-app $AGENT_HOME/bin/monitor.sh; echo "exit=$?"'
run_as agent-admin 'MONITOR_PORT=15999 $AGENT_HOME/bin/monitor.sh; echo "exit=$?"'
run "tail -2 $AGENT_LOG_DIR/monitor.log"

section "방화벽 비활성: [WARNING] 만 출력하고 계속 진행"
run "ufw disable"
run_as agent-admin '$AGENT_HOME/bin/monitor.sh | sed -n "/STATUS CHECK/,/INFO/p"; echo "exit=${PIPESTATUS[0]}"'
run "ufw --force enable && ufw status | head -1"

section "로그 용량 관리: 한도를 300바이트, 보관 4개로 낮춰 회전을 재현(운영값 10MB/10개)"
run_as agent-admin 'rm -rf /tmp/rotate-demo && mkdir -p /tmp/rotate-demo && for i in $(seq 1 12); do MONITOR_LOG=/tmp/rotate-demo/monitor.log MONITOR_MAX_BYTES=300 MONITOR_KEEP=4 $AGENT_HOME/bin/monitor.sh | grep rotated; done; ls -l /tmp/rotate-demo'
