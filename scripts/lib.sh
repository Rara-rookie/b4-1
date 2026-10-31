#!/bin/bash
# 단계 스크립트 공통 함수. 명령과 출력을 한 세트로 증거 로그에 남긴다.
#   step_begin 01-ssh "SSH 포트 변경과 root 원격 로그인 차단"
#   run  "sshd -T | grep -E '^(port|permitrootlogin) '"
#   run_as agent-admin "id"

B41_ROOT=${B41_ROOT:-/opt/b4-1}
EVIDENCE_DIR=${EVIDENCE_DIR:-$B41_ROOT/logs}
mkdir -p "$EVIDENCE_DIR"

export AGENT_HOME=/home/agent-admin/agent-app
export AGENT_PORT=15034
export AGENT_UPLOAD_DIR=$AGENT_HOME/upload_files
export AGENT_KEY_PATH=$AGENT_HOME/api_keys
export AGENT_LOG_DIR=/var/log/agent-app

step_begin() {
    STEP_LOG="$EVIDENCE_DIR/$1.log"
    : > "$STEP_LOG"
    {
        echo "# $2"
        echo "# 실행 시각: $(date '+%Y-%m-%d %H:%M:%S %Z')  호스트: $(hostname)  커널: $(uname -r)"
    } | tee -a "$STEP_LOG"
}

section() {
    printf '\n## %s\n' "$*" | tee -a "$STEP_LOG"
}

# 실패해도 멈추지 않는다. 실패 출력도 증거이므로 종료 코드를 함께 남긴다.
run() {
    printf '\n$ %s\n' "$1" | tee -a "$STEP_LOG"
    bash -c "$1" 2>&1 | tee -a "$STEP_LOG"
    local rc=${PIPESTATUS[0]}
    [ "$rc" -ne 0 ] && printf '(exit %d)\n' "$rc" | tee -a "$STEP_LOG"
    return 0
}

run_as() {
    local user=$1
    printf '\n%s$ %s\n' "$user" "$2" | tee -a "$STEP_LOG"
    su - "$user" -c "$2" 2>&1 | tee -a "$STEP_LOG"
    local rc=${PIPESTATUS[0]}
    [ "$rc" -ne 0 ] && printf '(exit %d)\n' "$rc" | tee -a "$STEP_LOG"
    return 0
}

note() {
    printf '# %s\n' "$*" | tee -a "$STEP_LOG"
}
