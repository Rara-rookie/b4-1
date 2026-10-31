#!/bin/bash
# 3. 제공 앱 실행 환경을 만들고 일반 계정(agent-admin)으로 실행한다.
set -u
. "$(dirname "$0")/lib.sh"
step_begin 04-app "환경 변수, 키 파일, 제공 앱 Boot Sequence 와 LISTEN 확인"

section "환경 변수(/etc/profile.d/agent-app.sh)"
install -m 644 "$B41_ROOT/agent/agent-app.env" /etc/profile.d/agent-app.sh
run "cat /etc/profile.d/agent-app.sh"
run_as agent-admin "env | grep '^AGENT_' | sort"

section "키 파일"
note "과제 문서의 파일명은 t_secret.key 이지만 제공 앱은 secret.key 를 읽는다. 둘 다 같은 내용으로 둔다."
for name in t_secret.key secret.key; do
    printf 'agent_api_key_test\n' > "$AGENT_KEY_PATH/$name"
done
run "chown agent-admin:agent-core $AGENT_KEY_PATH/*.key && chmod 640 $AGENT_KEY_PATH/*.key"
run "ls -l $AGENT_KEY_PATH && cat $AGENT_KEY_PATH/t_secret.key"

section "앱 배치(CPU 아키텍처에 맞는 바이너리 선택)"
case "$(uname -m)" in
    aarch64|arm64) BIN=agent-app-linux-arm64 ;;
    *)             BIN=agent-app-linux-x86 ;;
esac
rm -rf /tmp/agent-app-unzip && mkdir -p /tmp/agent-app-unzip
unzip -qo "$B41_ROOT/agent-app.zip" -d /tmp/agent-app-unzip
run "uname -m && ls -l /tmp/agent-app-unzip"
run "install -o agent-admin -g agent-common -m 750 /tmp/agent-app-unzip/$BIN $AGENT_HOME/agent-app && ls -l $AGENT_HOME/agent-app"

section "root 로 실행하면 거부된다"
pkill -x agent-app 2>/dev/null; sleep 1
run "cd $AGENT_HOME && timeout 5 ./agent-app 2>&1 | head -4"

section "agent-admin 으로 실행"
note "과제 원문은 포그라운드 실행 후 Ctrl+C 종료다. 자동화에서는 백그라운드로 띄우고 출력을 파일로 받는다."
# "cd && nohup ... &" 로 쓰면 & 가 목록 전체에 걸려 서브셸이 로그 파이프를 쥔 채 남고, tee 가 끝나지 않는다.
run_as agent-admin 'cd $AGENT_HOME; nohup ./agent-app > $AGENT_HOME/agent-app.out 2>&1 < /dev/null & echo "started (pid $!)"'
for _ in $(seq 1 30); do
    grep -q "Agent READY" "$AGENT_HOME/agent-app.out" 2>/dev/null && break
    sleep 1
done
sleep 2
run "sed -n '1,/Agent READY/p' $AGENT_HOME/agent-app.out"
run "ss -tlnp | grep ':15034'"
run "ps -o user,pid,ppid,pcpu,rss,args -C agent-app"
run "tail -5 $AGENT_LOG_DIR/agent_app.log"
