# b4-1 진행 계획

## 1. 요구사항 분해

| # | 요구사항 | 산출 | 검증 방법 |
|---|---|---|---|
| 1-1 | SSH 포트 20022, Root 원격 로그인 차단 | `sshd_config` 수정 | `sshd -T`, `ss -tulnp`, root/일반 계정 실제 키 접속 |
| 1-2 | UFW 활성, 20022/tcp·15034/tcp 만 허용 | UFW 규칙 | `ufw status verbose`, 허용 규칙 수 4개(v4/v6) |
| 2 | 계정 3개, 그룹 2개 | useradd/groupadd | `id`, `getent group` |
| 2 | upload_files=agent-common R/W, api_keys·로그=agent-core only | chown/chmod/setfacl | `ls -ld`, `getfacl`, 계정별 접근 시도 |
| 3 | 환경변수, 키 파일, 일반 계정 실행, Boot 5단계 OK, 15034 LISTEN | profile.d, 키 파일 | 앱 출력, `ss -tlnp`, `ps -o user` |
| 4 | monitor.sh 위치·소유·권한, 헬스체크 exit 1, 경고, 자원 수집, 로그 형식, 용량 관리 | `agent/monitor.sh` | 정상·프로세스 없음·포트 없음·방화벽 off·회전을 모두 실행 |
| 5 | agent-admin crontab 매분 | crontab | 등록 후 2분간 줄 수 증가 |
| 보너스 1 | report.sh 평균/최대/최소/샘플 수, 구간 지정 | `agent/report.sh` | 전체·최근 2분 구간 실행 |
| 보너스 2 | 7일 압축·아카이브, 30일 삭제, 예외 처리 | `agent/log-retention.sh` | `touch -d` 로 날짜를 되돌린 파일, 디렉터리 없음·권한 없음 |

제출물은 수행 내역서 1개와 `monitor.sh` 소스다. 내역서는 손으로 옮기지 않고 `logs/` 에서 발췌해 생성한다.

## 2. 단계별 실행 계획

| 단계 | 스크립트 | 비고 |
|---|---|---|
| 환경 | `setup.sh` → `env/Dockerfile` | Ubuntu 22.04 컨테이너, NET_ADMIN, 포트 20022/15034 매핑 |
| 1 | `step1-ssh.sh` | 설정 원본 `.orig` 보존, `sshd -t` 후 재시작 |
| 2 | `step2-firewall.sh` | `ufw --force reset` 으로 시작해 다시 실행해도 같은 결과 |
| 3 | `step3-accounts.sh` | 계정이 있으면 그룹 소속만 맞춘다. 같은 키를 root·agent-admin 에 등록해 접속 비교 |
| 4 | `step4-app.sh` | 아키텍처별 바이너리 선택, root 실행 거부도 기록 |
| 5 | `step5-monitor.sh` | 작성자 agent-dev 가 `install -g agent-core -m 750` |
| 6 | `step6-cron.sh` | 분 경계를 두 번 넘길 때까지(125초) 대기 |
| 7 | `step7-bonus.sh` | 보너스 두 가지 |
| 판정 | `run-all.sh` | 상태를 다시 조회해 체크리스트 PASS/FAIL |
| 문서 | `make-report.sh` | `docs/report.md` 생성 |

## 3. 환경 실측

| 항목 | 값 | 근거 |
|---|---|---|
| Docker | 29.6.2, linux/x86_64 | `docker info` |
| 서버 OS | Ubuntu 22.04 (ubuntu:22.04 이미지) | `env/Dockerfile` |
| 커널 | 5.15.167.4-microsoft-standard-WSL2 (Windows Docker Desktop) | `logs/01-ssh.log` 머리글 |
| 제공 앱 | `agent-app-linux-x86`, `agent-app-linux-arm64` (PyInstaller) | `logs/04-app.log` |
| 앱 키 경로 | `AGENT_KEY_PATH` 는 디렉터리, 파일명 `secret.key` | 실측: `Key Path Mismatch`, `Missing File: secret.key` |
| 앱 로그 | `/var/log/agent-app/agent_app.log` | `logs/04-app.log` |

## 4. 위험 요소와 대응

| 위험 | 대응 |
|---|---|
| 컨테이너에서 UFW 가 동작하지 않을 수 있다 | 사전 실험으로 `--cap-add NET_ADMIN` 에서 `ufw enable` 성공 확인 |
| systemd 부재로 `systemctl` 이 없다 | sshd 직접 기동(`-E` 로 인증 로그 파일화), `service cron start` |
| cron 이 컨테이너에서 사용자 작업을 실행하지 않는다 | `pam_loginuid` 비활성화, 2분 대기 후 줄 수로 검증 |
| 앱을 백그라운드로 띄우면 증거 로그 파이프가 닫히지 않는다 | `cd ...; nohup ... < /dev/null &` 로 `&` 가 nohup 에만 걸리게 한다 |
| Ubuntu 22.04 홈 디렉터리 기본 750 | `setfacl -m g:agent-common:--x /home/agent-admin` 로 통과만 허용 |
| agent-admin 은 `ufw status` 권한이 없다 | sudoers 에 그 명령 하나만 허용, 불가하면 `ufw.conf` 로 대체 |
| Windows 체크아웃 시 CRLF | `.gitattributes` 로 LF 고정, 복사 후 `sed 's/\r$//'` |
| 과제 문서와 제공 앱의 키 경로가 다르다 | 앱 실측을 따르고 두 파일명을 모두 만든 뒤 문서에 근거를 남긴다 |
| 포트 충돌 | `HOST_SSH_PORT`, `HOST_APP_PORT` 로 호스트 쪽 포트만 바꾼다 |
