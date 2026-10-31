#!/bin/bash
# 5. agent-admin crontab 에 monitor.sh 를 매분 등록하고 로그가 스스로 늘어나는지 확인한다.
set -u
. "$(dirname "$0")/lib.sh"
step_begin 06-cron "crontab 매분 실행 등록과 자동 누적 확인"

section "cron 데몬"
run "service cron start >/dev/null 2>&1; service cron status"

section "agent-admin crontab 등록"
cat > /tmp/agent-admin.cron <<'EOF'
# 매분 상태 점검. 콘솔 출력은 버리고 오류만 남긴다(monitor.log 에는 스크립트가 직접 쓴다).
* * * * * /home/agent-admin/agent-app/bin/monitor.sh > /dev/null 2>> /var/log/agent-app/monitor-cron.err
# 매일 03:10 로그 보존 정책(보너스 2)
10 3 * * * /home/agent-admin/agent-app/bin/log-retention.sh >> /var/log/agent-app/retention.out 2>&1
EOF
run "crontab -u agent-admin /tmp/agent-admin.cron && crontab -l -u agent-admin"

section "자동 실행 확인: 등록 직후와 2분 뒤 줄 수 비교"
before=$(wc -l < "$AGENT_LOG_DIR/monitor.log")
run "date '+%F %T'; wc -l $AGENT_LOG_DIR/monitor.log; tail -2 $AGENT_LOG_DIR/monitor.log"
note "분 경계를 두 번 넘길 때까지 기다린다(약 125초)."
sleep 125
after=$(wc -l < "$AGENT_LOG_DIR/monitor.log")
run "date '+%F %T'; wc -l $AGENT_LOG_DIR/monitor.log; tail -4 $AGENT_LOG_DIR/monitor.log"
note "cron 이 추가한 줄: $(( after - before ))줄 (기대: 2줄 이상)"
run "cat $AGENT_LOG_DIR/monitor-cron.err 2>/dev/null || echo '(cron 오류 없음)'"
