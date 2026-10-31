#!/bin/bash
# 1-1. SSH 포트를 20022 로 바꾸고 root 원격 로그인을 막는다.
set -u
. "$(dirname "$0")/lib.sh"
step_begin 01-ssh "SSH 포트 변경(20022)과 root 원격 로그인 차단"

CONF=/etc/ssh/sshd_config
section "설정 전 상태"
run "grep -nE '^#?(Port|PermitRootLogin) ' $CONF"

section "설정 변경(원본은 .orig 로 보존)"
[ -f "$CONF.orig" ] || cp "$CONF" "$CONF.orig"
run "sed -i -E 's/^#?Port .*/Port 20022/; s/^#?PermitRootLogin .*/PermitRootLogin no/' $CONF"
run "grep -nE '^(Port|PermitRootLogin) ' $CONF"
run "sshd -t && echo 'sshd 설정 문법 검사 통과'"

section "sshd 재시작과 리슨 확인"
# 컨테이너에는 syslog 가 없으므로 인증 기록을 파일로 남기도록 -E 로 띄운다.
pkill -x sshd 2>/dev/null; sleep 1
run "/usr/sbin/sshd -E /var/log/sshd_auth.log && echo 'sshd started'"
sleep 1
run "sshd -T | grep -E '^(port|permitrootlogin) '"
run "ss -tulnp | grep sshd"
note "root 원격 로그인 거부는 계정 생성 뒤 03 단계에서 실제 접속으로 검증한다."
