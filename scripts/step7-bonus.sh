#!/bin/bash
# 보너스 1(report.sh)과 보너스 2(시간 기반 보존 정책)를 실행한다.
set -u
. "$(dirname "$0")/lib.sh"
step_begin 07-bonus "보너스: report.sh 통계, 로그 압축/아카이브/삭제"

section "보너스 1: 전체 구간 통계"
run_as agent-admin '$AGENT_HOME/bin/report.sh'
section "보너스 1: 최근 2분 구간만"
run_as agent-admin '$AGENT_HOME/bin/report.sh "$(date -d "-2 min" "+%F %T")" "$(date "+%F %T")"'

section "보너스 2: 날짜를 되돌린 파일로 7일/30일 규칙 재현"
printf 'old line\n' > "$AGENT_LOG_DIR/old-worker.log"
printf 'recent line\n' > "$AGENT_LOG_DIR/recent-worker.log"
printf 'ancient\n' | gzip > /var/log/monitor/agent-app/archive/ancient.log.20260801.gz
touch -d '8 days ago' "$AGENT_LOG_DIR/old-worker.log"
touch -d '3 days ago' "$AGENT_LOG_DIR/recent-worker.log"
touch -d '31 days ago' /var/log/monitor/agent-app/archive/ancient.log.20260801.gz
chown agent-admin:agent-core "$AGENT_LOG_DIR"/*-worker.log /var/log/monitor/agent-app/archive/*.gz
run "ls -l --time-style=+%F $AGENT_LOG_DIR /var/log/monitor/agent-app/archive"
run_as agent-admin '$AGENT_HOME/bin/log-retention.sh'
run "ls -l --time-style=+%F $AGENT_LOG_DIR /var/log/monitor/agent-app/archive"

section "보너스 2 예외 처리"
run_as agent-admin '$AGENT_HOME/bin/log-retention.sh'
run_as agent-admin 'LOG_SRC=/var/log/no-such-dir $AGENT_HOME/bin/log-retention.sh; echo "exit=$?"'
install -m 755 "$B41_ROOT/agent/log-retention.sh" /tmp/log-retention-test.sh
run_as agent-test 'bash /tmp/log-retention-test.sh; echo "exit=$?"'
