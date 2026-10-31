#!/bin/bash
# 2. 역할 계정·그룹을 만들고 공유/보안 디렉터리를 분리한다. SSH 접속 정책도 실제 접속으로 검증한다.
set -u
. "$(dirname "$0")/lib.sh"
step_begin 03-accounts "계정/그룹 생성, 디렉터리 권한(ACL), SSH 접속 검증"

section "그룹"
run "groupadd -f agent-common && groupadd -f agent-core"

section "계정 (다시 실행하면 그룹 소속만 맞춘다)"
for spec in "agent-admin:agent-common,agent-core" "agent-dev:agent-common,agent-core" "agent-test:agent-common"; do
    user=${spec%%:*}; groups=${spec#*:}
    if id "$user" >/dev/null 2>&1; then
        run "usermod -aG $groups $user"
    else
        run "useradd -m -s /bin/bash -G $groups $user"
    fi
done
run "id agent-admin; id agent-dev; id agent-test"
run "getent group agent-common agent-core"

section "디렉터리 생성"
run "mkdir -p $AGENT_UPLOAD_DIR $AGENT_KEY_PATH $AGENT_HOME/bin $AGENT_LOG_DIR /var/log/monitor/agent-app/archive"

section "권한 부여"
note "Ubuntu 22.04 는 홈을 750 으로 만든다. 다른 계정이 AGENT_HOME 에 닿도록 목록 조회 없이 통과(x)만 허용한다."
run "setfacl -m g:agent-common:--x /home/agent-admin"
run "chown agent-admin:agent-common $AGENT_HOME && chmod 750 $AGENT_HOME"
note "upload_files: agent-common(admin, dev, test) 읽기/쓰기. setgid 와 기본 ACL 로 새 파일도 같은 그룹 권한을 물려받는다."
run "chown agent-admin:agent-common $AGENT_UPLOAD_DIR && chmod 2770 $AGENT_UPLOAD_DIR"
run "setfacl -m g:agent-common:rwx -d -m g:agent-common:rwx $AGENT_UPLOAD_DIR"
note "api_keys, /var/log/agent-app: agent-core(admin, dev)만 읽기/쓰기. others 는 권한 없음."
run "chown agent-admin:agent-core $AGENT_KEY_PATH && chmod 2770 $AGENT_KEY_PATH"
run "setfacl -m g:agent-core:rwx -d -m g:agent-core:rwx $AGENT_KEY_PATH"
run "chown agent-admin:agent-core $AGENT_LOG_DIR && chmod 2770 $AGENT_LOG_DIR"
run "setfacl -m g:agent-core:rwx -d -m g:agent-core:rwx $AGENT_LOG_DIR"
note "bin: monitor.sh 작성자 agent-dev 소유, agent-core 는 읽기·실행만."
run "chown agent-dev:agent-core $AGENT_HOME/bin && chmod 2750 $AGENT_HOME/bin"
run "chown -R agent-admin:agent-core /var/log/monitor && chmod -R 2770 /var/log/monitor"

section "확인: 소유/권한/ACL"
run "ls -ld /home/agent-admin $AGENT_HOME $AGENT_UPLOAD_DIR $AGENT_KEY_PATH $AGENT_HOME/bin $AGENT_LOG_DIR"
run "getfacl -p $AGENT_UPLOAD_DIR $AGENT_KEY_PATH $AGENT_LOG_DIR"

section "확인: 계정별 실제 접근"
run_as agent-test "touch $AGENT_UPLOAD_DIR/from-agent-test.txt && ls -l $AGENT_UPLOAD_DIR/from-agent-test.txt"
run_as agent-dev "touch $AGENT_UPLOAD_DIR/from-agent-dev.txt && ls -l $AGENT_UPLOAD_DIR/from-agent-dev.txt"
note "agent-test 는 보안 디렉터리에 접근할 수 없어야 한다(Permission denied 가 정상)."
run_as agent-test "ls $AGENT_KEY_PATH"
run_as agent-test "touch $AGENT_LOG_DIR/agent-test-probe.log"
run_as agent-dev "touch $AGENT_KEY_PATH/.probe && rm $AGENT_KEY_PATH/.probe && echo 'agent-dev: api_keys 읽기/쓰기 가능'"
run_as agent-dev "touch $AGENT_LOG_DIR/.probe && rm $AGENT_LOG_DIR/.probe && echo 'agent-dev: /var/log/agent-app 읽기/쓰기 가능'"

section "SSH 접속 검증: 20022 에서 일반 계정은 허용, root 는 거부"
KEY=/root/.ssh/id_b41
[ -f "$KEY" ] || { mkdir -p /root/.ssh && chmod 700 /root/.ssh && ssh-keygen -q -t ed25519 -N '' -f "$KEY"; }
install -d -m 700 -o agent-admin -g agent-admin /home/agent-admin/.ssh
cp "$KEY.pub" /home/agent-admin/.ssh/authorized_keys
chown agent-admin:agent-admin /home/agent-admin/.ssh/authorized_keys && chmod 600 /home/agent-admin/.ssh/authorized_keys
cp "$KEY.pub" /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys
note "같은 키를 root 와 agent-admin 양쪽에 등록했다. 결과가 갈리면 차이는 PermitRootLogin 뿐이다."
SSH="ssh -i $KEY -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
run "$SSH -p 20022 agent-admin@127.0.0.1 'echo login-ok: \$(whoami)@\$(hostname)'"
run "$SSH -p 20022 root@127.0.0.1 'echo root-login-should-not-happen'"
run "$SSH -o ConnectTimeout=3 -p 22 agent-admin@127.0.0.1 true"
run "grep -E 'ROOT LOGIN REFUSED|Accepted publickey' /var/log/sshd_auth.log | tail -4"
