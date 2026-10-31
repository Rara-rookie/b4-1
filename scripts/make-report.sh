#!/bin/bash
# logs/ 의 실제 출력을 발췌해 요구사항 수행 내역서(docs/report.md)를 만든다.
# 손으로 옮겨 적지 않으므로, 다시 실행하면 그 실행의 증거로 내역서가 다시 쓰인다.
set -u
. "$(dirname "$0")/lib.sh"
OUT=${REPORT_OUT:-$B41_ROOT/docs/report.md}
mkdir -p "$(dirname "$OUT")"
L=$EVIDENCE_DIR
F='```'

# 로그에서 정규식이 처음 나온 줄부터 다음 '## ' 머리글 직전까지(최대 n줄)를 뽑는다.
cut_from() {
    awk -v pat="$2" -v n="${3:-40}" '
        !on && $0 ~ pat { on = 1 }
        on { if (c > 0 && /^## /) exit; print; if (++c >= n) exit }
    ' "$L/$1"
}

cmd_block() {   # $1 로그, $2 명령 정규식, $3 최대 줄: "$ 명령" 줄과 그 출력만
    awk -v pat="$2" -v n="${3:-20}" '
        !on && ($0 ~ "^[a-z-]*\\$ " pat) { on = 1 }
        on { if (c > 0 && (/^[a-z-]*\$ / || /^## /)) exit; print; if (++c >= n) exit }
    ' "$L/$1"
}

{
cat <<EOF
# b4-1 요구사항 수행 내역서

- 생성: $(date '+%Y-%m-%d %H:%M:%S %Z') (scripts/make-report.sh)
- 환경: $(sed -n '2p' "$L/01-ssh.log" | sed 's/^# //')
- 원본 증거: ${F%??}logs/${F%??} 아래 단계별 로그. 이 문서의 모든 출력은 그 로그에서 그대로 발췌했다.

## 0. 필수 증거 체크리스트

실제 상태를 다시 조회해 판정한 결과다(logs/00-checklist.log).

${F}text
$(grep -E '^\[(PASS|FAIL)\]' "$L/00-checklist.log")
${F}

| 필수 증거 | 근거 위치 |
|---|---|
| SSH 포트 20022, Root 원격 접속 차단 | 1-1, logs/01-ssh.log, logs/03-accounts.log |
| UFW 활성, 20022/tcp·15034/tcp 만 허용 | 1-2, logs/02-firewall.log |
| 계정/그룹 생성 | 2-1, logs/03-accounts.log |
| 디렉터리 구조·권한(ACL) | 2-2, logs/03-accounts.log |
| Boot Sequence 5단계 [OK], Agent READY | 3, logs/04-app.log |
| monitor.sh 실행 결과 | 4, logs/05-monitor.log |
| monitor.log 누적 기록 | 4·5, logs/05-monitor.log, logs/06-cron.log |
| crontab 매분 실행과 1분 후 로그 증가 | 5, logs/06-cron.log |

## 1. 기본 보안 및 네트워크

### 1-1. SSH 포트 변경과 Root 원격 로그인 차단

설정 파일(/etc/ssh/sshd_config)의 두 줄을 바꾸고 문법 검사 후 재시작했다.

${F}text
$(cmd_block 01-ssh.log "sed -i" 3)
$(cmd_block 01-ssh.log "grep -nE '\\^\\(Port" 4)
$(cmd_block 01-ssh.log "sshd -T" 4)
$(cmd_block 01-ssh.log "ss -tulnp" 4)
${F}

같은 공개키를 root 와 agent-admin 에 등록하고 20022 로 접속했다. 결과가 갈리는 이유는 PermitRootLogin 뿐이다.

${F}text
$(cut_from 03-accounts.log "agent-admin@127.0.0.1" 30)
${F}

### 1-2. 방화벽(UFW)

${F}text
$(cmd_block 02-firewall.log "ufw default deny" 3)
$(cmd_block 02-firewall.log "ufw allow 20022" 3)
$(cmd_block 02-firewall.log "ufw allow 15034" 3)
$(cmd_block 02-firewall.log "ufw status verbose" 16)
${F}

## 2. 계정/그룹/권한 체계

### 2-1. 계정과 그룹

${F}text
$(cmd_block 03-accounts.log "id agent-admin" 5)
$(cmd_block 03-accounts.log "getent group" 4)
${F}

### 2-2. 디렉터리 구조와 권한(ACL)

${F}text
$(cmd_block 03-accounts.log "ls -ld" 8)
$(cmd_block 03-accounts.log "getfacl -p" 40)
${F}

계정별로 실제 접근을 시도한 결과다(Permission denied 가 정책대로 막힌 것).

${F}text
$(cut_from 03-accounts.log "확인: 계정별 실제 접근" 30)
${F}

## 3. 애플리케이션 실행 환경

${F}text
$(cmd_block 04-app.log "cat /etc/profile.d/agent-app.sh" 10)
$(cut_from 04-app.log "agent-admin\\$ env" 8)
$(cmd_block 04-app.log "ls -l .*api_keys" 6)
${F}

> 과제 문서는 ${F%??}AGENT_KEY_PATH=\$AGENT_HOME/api_keys/t_secret.key${F%??} 로 적었지만, 제공 앱은 디렉터리 경로를 요구하고(${F%??}Key Path Mismatch. Expected: .../api_keys${F%??}) 그 안의 ${F%??}secret.key${F%??} 를 읽었다. 실측에 맞춰 디렉터리를 지정하고 두 파일명을 같은 내용으로 두었다.

root 실행 거부와 일반 계정 실행 결과:

${F}text
$(cut_from 04-app.log "root 로 실행하면 거부된다" 10)
$(cmd_block 04-app.log "sed -n '1,/Agent READY/p'" 20)
$(cmd_block 04-app.log "ss -tlnp" 3)
$(cmd_block 04-app.log "ps -o user" 4)
${F}

## 4. monitor.sh

### 배치 정책과 실행

${F}text
$(cmd_block 05-monitor.log "stat -c" 5)
$(cmd_block 05-monitor.log "cat /etc/sudoers.d" 3)
$(cut_from 05-monitor.log "정상 실행" 36)
${F}

### 실패·경고 경로

${F}text
$(cut_from 05-monitor.log "Health Check 실패 시 exit 1" 22)
$(cut_from 05-monitor.log "방화벽 비활성" 16)
$(cut_from 05-monitor.log "권한 없는 계정" 6)
${F}

### 로그 용량 관리

운영값은 10MB/10개다. 같은 로직을 300바이트/4개로 낮춰 회전이 실제로 일어나는지 확인했다.

${F}text
$(cut_from 05-monitor.log "로그 용량 관리" 24)
${F}

## 5. 자동 실행(cron)

${F}text
$(cut_from 06-cron.log "agent-admin crontab 등록" 12)
$(cut_from 06-cron.log "자동 실행 확인" 20)
${F}

## 6. 보너스

### 보너스 1: report.sh

${F}text
$(cut_from 07-bonus.log "보너스 1: 전체 구간" 22)
${F}

### 보너스 2: 시간 기반 보존 정책

${F}text
$(cut_from 07-bonus.log "보너스 2: 날짜를" 30)
$(cut_from 07-bonus.log "보너스 2 예외 처리" 16)
${F}
EOF
} > "$OUT"
echo "[DONE] $OUT ($(wc -l < "$OUT") lines)"
