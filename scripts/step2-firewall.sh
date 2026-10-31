#!/bin/bash
# 1-2. UFW 를 켜고 인바운드는 20022/tcp(SSH), 15034/tcp(APP)만 허용한다.
set -u
. "$(dirname "$0")/lib.sh"
step_begin 02-firewall "UFW 활성화와 20022/tcp, 15034/tcp 만 허용"

section "초기화(다시 실행해도 같은 규칙만 남도록)"
run "ufw --force reset"

section "기본 정책과 허용 규칙"
run "ufw default deny incoming"
run "ufw default allow outgoing"
run "ufw allow 20022/tcp comment 'SSH'"
run "ufw allow 15034/tcp comment 'AGENT APP'"
run "ufw --force enable"

section "검증"
run "ufw status verbose"
run "ufw status numbered"
run "grep '^ENABLED' /etc/ufw/ufw.conf"
note "22/tcp 규칙이 없어야 한다(기본 SSH 포트는 막힘):"
run "ufw status | grep -E '^22/tcp' || echo '22/tcp 허용 규칙 없음'"
