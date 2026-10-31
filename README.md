# b4-1. 컴퓨터가 알아서 자기 상태를 점검하게 만들기

Ubuntu 22.04 서버에 SSH·방화벽·역할 계정·ACL 을 설정하고, 제공 앱(agent-app)을 일반 계정으로 띄운 뒤
`monitor.sh` 로 헬스체크·자원 수집·로그 기록을 매분 자동 실행한다.
서버는 Docker 컨테이너로 만들고, 스크립트 하나로 환경 생성부터 증거 수집까지 끝난다.

## 한 번에 실행

```bash
./setup.sh
```

| 명령 | 하는 일 |
|---|---|
| `./setup.sh` | 이미지 빌드 → 서버 컨테이너 생성 → 1~7단계 실행(약 4분) → `logs/`, `docs/report.md` 생성 |
| `./setup.sh shell` | 서버에 root 셸로 접속 |
| `./setup.sh ssh` | 호스트에서 `127.0.0.1:20022` 로 agent-admin SSH 접속 |
| `./setup.sh clean` | 서버 컨테이너 삭제 |

필요한 것은 실행 중인 Docker(Desktop)와 이 폴더의 `agent-app.zip` 뿐이다.
호스트의 20022·15034 포트가 이미 쓰이고 있으면 `HOST_SSH_PORT=21022 HOST_APP_PORT=25034 ./setup.sh` 로 바꾼다.

**iMac(평가 환경)**: Docker Desktop for Mac 에서 그대로 실행한다. 컨테이너 아키텍처(`uname -m`)를 보고
Apple Silicon 이면 `agent-app-linux-arm64`, Intel 이면 `agent-app-linux-x86` 을 자동으로 고른다.
Windows 에서만 필요한 처리(Git Bash 경로 변환 차단 `MSYS_NO_PATHCONV`, CRLF 제거)는 macOS 에서는 아무 영향이 없다.

## 제출물

| 제출물 | 위치 |
|---|---|
| 요구사항 수행 내역서 | [docs/report.md](docs/report.md) — 필수 증거 체크리스트와 단계별 명령·출력 발췌 |
| 자동화 스크립트 | [agent/monitor.sh](agent/monitor.sh) (서버의 `$AGENT_HOME/bin/monitor.sh`) |
| 보너스 1·2 | [agent/report.sh](agent/report.sh), [agent/log-retention.sh](agent/log-retention.sh) |
| 원본 증거 | [logs/](logs/) — 명령(`$ cmd`)과 출력을 한 세트로 기록 |

## 필수 증거 체크리스트

`logs/00-checklist.log` 는 실행이 끝난 뒤 서버 상태를 다시 조회해 판정한다.

| 필수 증거 | 판정 | 근거 |
|---|---|---|
| SSH 포트 20022, Root 원격 접속 차단 | PASS | `logs/01-ssh.log`, `logs/03-accounts.log`(root 키 접속 거부) |
| UFW 활성, 20022/tcp·15034/tcp 만 허용 | PASS | `logs/02-firewall.log` |
| 계정 agent-admin/dev/test, 그룹 agent-common/core | PASS | `logs/03-accounts.log` |
| 디렉터리 구조와 권한(ACL) | PASS | `logs/03-accounts.log` |
| Boot Sequence 5단계 [OK], Agent READY | PASS | `logs/04-app.log` |
| monitor.sh 실행 결과(프로세스/포트/리소스/경고) | PASS | `logs/05-monitor.log` |
| monitor.log 누적 기록 | PASS | `logs/05-monitor.log`, `logs/06-cron.log` |
| crontab 매분 등록, 1분 후 로그 증가 | PASS | `logs/06-cron.log` |

## 구성

```
b4-1/
├── setup.sh               호스트에서 실행하는 진입점
├── env/Dockerfile         Ubuntu 22.04 + openssh-server, ufw, acl, cron
├── scripts/               서버 안에서 도는 단계 스크립트
│   ├── lib.sh             명령과 출력을 증거 로그로 남기는 공통 함수
│   ├── step1-ssh.sh       포트 20022, PermitRootLogin no
│   ├── step2-firewall.sh  UFW deny incoming + 20022/15034 허용
│   ├── step3-accounts.sh  계정·그룹·디렉터리·ACL, SSH 접속 검증
│   ├── step4-app.sh       환경변수·키 파일·앱 실행(agent-admin)
│   ├── step5-monitor.sh   monitor.sh 배치와 정상/실패/경고/회전 실행
│   ├── step6-cron.sh      crontab 등록과 자동 누적 확인
│   ├── step7-bonus.sh     report.sh, 로그 보존 정책
│   ├── run-all.sh         1~7단계와 체크리스트 판정
│   └── make-report.sh     logs/ 발췌로 docs/report.md 생성
├── agent/                 서버에 설치되는 파일
│   ├── monitor.sh  report.sh  log-retention.sh
│   └── agent-app.env      /etc/profile.d/agent-app.sh
├── docs/report.md         요구사항 수행 내역서
└── logs/                  단계별 증거
```

## 설정 요약

| 항목 | 값 |
|---|---|
| SSH | `Port 20022`, `PermitRootLogin no` (`/etc/ssh/sshd_config`) |
| 방화벽 | UFW `default deny incoming`, 허용 `20022/tcp`, `15034/tcp` |
| 계정 | agent-admin(agent-common, agent-core), agent-dev(agent-common, agent-core), agent-test(agent-common) |
| `$AGENT_HOME` | `/home/agent-admin/agent-app` (agent-admin:agent-common 750) |
| `upload_files` | agent-admin:agent-common 2770, ACL `group:agent-common:rwx` + 기본 ACL |
| `api_keys`, `/var/log/agent-app` | agent-admin:agent-core 2770, ACL `group:agent-core:rwx` + 기본 ACL |
| `$AGENT_HOME/bin/monitor.sh` | agent-dev:agent-core 750 |
| cron | agent-admin: `* * * * * .../monitor.sh`, `10 3 * * * .../log-retention.sh` |
| sudoers | `agent-admin ALL=(root) NOPASSWD: /usr/sbin/ufw status` 한 줄 |

### 제공 앱이 요구하는 값

과제 문서는 `AGENT_KEY_PATH=$AGENT_HOME/api_keys/t_secret.key` 로 적었지만, 제공 앱은
`Key Path Mismatch. Expected: /home/agent-admin/agent-app/api_keys` 로 **디렉터리 경로**를 요구하고
그 안의 **`secret.key`** 를 읽는다. 그래서 `AGENT_KEY_PATH=$AGENT_HOME/api_keys` 로 두고
`t_secret.key`(과제 문서)와 `secret.key`(앱)를 같은 내용으로 만든다.

## monitor.sh 동작

| 구분 | 방법 | 결과 |
|---|---|---|
| 프로세스 | `pgrep -n -x agent-app` | 없으면 `[FAIL]`, 로그에 `[ERROR]`, **exit 1** |
| 포트 | `ss -Hltn "sport = :15034"` | 리슨이 없으면 `[FAIL]`, **exit 1** |
| 방화벽 | `sudo -n ufw status`, 불가하면 `/etc/ufw/ufw.conf` | 비활성이면 `[WARNING]` 만 출력 |
| CPU | `/proc/stat` 1초 간격 두 번, idle+iowait 제외 비율 | > 20% `[WARNING]` |
| MEM | `(MemTotal - MemAvailable) / MemTotal` | > 10% `[WARNING]` |
| DISK | `df -P /` Use% | > 80% `[WARNING]` |
| 로그 | `[YYYY-MM-DD HH:MM:SS] PID:.. CPU:..% MEM:..% DISK_USED:..%` | `/var/log/agent-app/monitor.log` |
| 용량 | 10MB 이상이면 `.1`~`.9` 로 밀어 최대 10개 유지 | 스크립트 내부 회전 |
| 중복 실행 | `flock -n` | 이전 회차가 돌고 있으면 건너뜀 |

제공 앱은 PyInstaller 로 묶여 부트로더와 워커가 같은 이름으로 두 개 뜬다. `pgrep -n` 으로 나중에 뜬 워커 PID 를 쓴다.

## 컨테이너라서 다르게 처리한 것

| 상황 | 처리 |
|---|---|
| systemd 가 없다 | `sshd -E /var/log/sshd_auth.log`, `service cron start` 로 직접 띄운다 |
| UFW 가 iptables 규칙을 바꾼다 | `--cap-add NET_ADMIN` (컨테이너 네트워크 네임스페이스 안에서만 적용, `--privileged` 는 쓰지 않음) |
| cron 이 사용자 작업을 건너뛴다 | 로그인 세션이 없어 실패하는 `pam_loginuid` 를 `/etc/pam.d/cron` 에서 끈다 |
| `TZ` 가 `su -` 로그인 셸에 전달되지 않는다 | `/etc/localtime` 을 Asia/Seoul 로 고정 |

실제 VM(iMac 의 Ubuntu VM 등)에서 수작업으로 할 때는 위 우회가 필요 없다.
`systemctl restart ssh`, `systemctl enable --now cron` 을 쓰면 된다.
