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
│   ├── agent-app.logrotate  logrotate 설치 예시(실행 경로에서는 쓰지 않음)
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

## 설계 근거와 운영 메모

### 종료 코드와 알림 흐름

| 종료 코드 | 의미 | 로그 | 운영 조치 |
|---|---|---|---|
| 0 | 정상, 또는 임계값 초과 경고(CPU 20%, MEM 10%, DISK 80%, 방화벽 비활성) | 한 줄 기록, 경고는 `[WARNING]` | 사람이 로그를 보고 판단한다. 서비스는 계속 돈다 |
| 1 | 헬스체크 실패: 프로세스 없음 또는 포트 미리슨 | `[ERROR]` 를 기록하고 종료 | 즉시 조치 대상. cron 의 stderr 는 `monitor-cron.err` 에 남는다 |

경고는 "곧 문제가 될 수 있음", 실패는 "지금 서비스가 죽었음"이라 종료 코드를 나눴다. 이번 과제에는 메일·메신저 알림이 없고, 알림을 붙인다면 `monitor.sh` 의 종료 코드 1 을 `|| 알림 명령` 으로 받는다.

### `>` 와 `>>` 의 차이

`>` 는 파일을 비우고 새로 쓰고(덮어쓰기), `>>` 는 기존 내용 뒤에 이어 쓴다(추가). 로그를 `>` 로 쓰면 매분 이전 기록이 사라지므로 `monitor.log` 는 항상 `>>` 로 쓴다.
cron 줄 `monitor.sh > /dev/null 2>> monitor-cron.err` 에서 표준 출력(점검 화면용 출력)은 버리고, 표준 오류만 파일에 **누적**해 cron 단계의 오류를 남긴다.
`monitor.sh` 안에서도 로그 기록은 모두 `>> "$LOG_FILE"`, 중복 실행 방지 잠금 파일은 `exec 9>>` 로 연다(내용을 지우지 않고 파일만 연다).

### 로그 회전: logrotate 대신 스크립트를 쓴 이유

과제는 "logrotate 사용 또는 스크립트 로직 구현"을 자유 선택으로 두었고, 이 구현은 스크립트(`monitor.sh` 의 `rotate_log`)를 택했다.

| 기준 | 스크립트 회전(채택) | logrotate |
|---|---|---|
| 실행 시점 | monitor.sh 가 돌 때마다(매분) 크기 검사 | 보통 cron.daily 로 하루 한 번 |
| 설치 | `monitor.sh` 하나로 끝, 컨테이너에서도 동작 | 패키지와 `/etc/logrotate.d/` 설정이 필요 |
| 시험 | `MONITOR_MAX_BYTES=300` 처럼 한도를 낮춰 회전을 재현(`logs/05-monitor.log`) | `logrotate -d`/`-f` 로 확인 |
| 기능 | 이름 밀기(`.1`~`.9`)만 | 압축, 지연 압축, 사후 스크립트, 상태 파일 |

운영에서 로그 종류가 많아지면 logrotate 가 더 표준적이다. 동등한 설정 예시는 [agent/agent-app.logrotate](agent/agent-app.logrotate)(`size 10M`, `rotate 9`)에 두었고 `logrotate -d` 로 문법을 확인했다. 실행 경로에서는 쓰이지 않는다.

### SSH 위협 모델

| 위협 | 설명 | 이번 대응 | 추가로 권장하는 대응 |
|---|---|---|---|
| 자동 스캔과 무차별 대입 | 인터넷의 봇이 22번 포트와 root 계정에 암호를 대입한다 | 기본 포트 22 → 20022 로 노출을 줄이고, root 원격 로그인 차단(`PermitRootLogin no`), UFW 로 20022·15034 외 차단 | 키 인증만 허용(`PasswordAuthentication no`), `fail2ban` 으로 반복 실패 IP 차단, `ufw limit 20022/tcp` 로 연결 빈도 제한 |
| 권한 상승 | root 가 뚫리면 서버 전체가 넘어간다 | root 직접 접속 금지, 일반 계정(agent-admin)으로 접속 후 필요한 명령만 sudo(`ufw status` 한 줄) | 접속 허용 계정 목록(`AllowUsers`) |

포트 변경은 스캐너를 피하는 정도의 난독화이고 보안의 본질이 아니다. 실제 방어는 root 차단과 인증 강화, 방화벽이다.

### 도구와 옵션을 고른 이유

| 대상 | 선택 | 이유 |
|---|---|---|
| 방화벽 | UFW | Ubuntu 기본 도구이고 명령이 짧다. firewalld 는 RHEL 계열 기본이라 이번 Ubuntu 22.04 환경과 맞지 않는다 |
| 포트 확인 | `ss -Hltn "sport = :15034"` | `netstat` 은 net-tools 패키지로 구식이고 기본 설치가 아니다. `ss` 는 iproute2 에 있어 컨테이너에도 있고 필터(`sport =`)와 `-H`(머리글 없음)로 스크립트에서 다루기 쉽다 |
| 프로세스 확인 | `pgrep -n -x agent-app` | `-x` 로 이름이 정확히 같은 것만, `-n` 으로 가장 나중에 뜬 워커를 고른다. PyInstaller 앱은 부트로더와 워커가 같은 이름으로 둘 뜬다 |
| CPU | `/proc/stat` 1초 간격 두 번 | `top`/`ps` 의 출력 형식에 의존하지 않고, 두 시점의 누적 tick 차이로 구간 사용률을 구한다. 계산식: (전체 증가량 - (idle+iowait) 증가량) × 100 / 전체 증가량, 단위 % |
| MEM | `/proc/meminfo` 의 `MemAvailable` | 회수 가능한 캐시를 사용량에서 뺀다. (MemTotal - MemAvailable) × 100 / MemTotal, 단위 % |
| DISK | `df -P /` 의 Use% | `-P` 로 줄바꿈 없는 POSIX 형식을 고정해 5번째 필드를 안정적으로 읽는다 |
| 계정 생성 | `useradd -m -s /bin/bash -G <그룹>` | `-m` 홈 디렉터리 생성, `-s` 로그인 셸 지정, `-G` 보조 그룹 지정. 비밀번호는 설정하지 않아 키·`su` 로만 접근한다 |

### 포트 미개방 진단 순서

프로세스는 있는데 포트가 안 열리면(`[ERROR] port 15999 is not listening`) 다음 순서로 본다.
1. `ss -tlnp | grep <포트>` — 리슨 자체가 있는지, 있다면 어느 프로세스가 쥐고 있는지(다른 프로세스가 포트를 점유한 경우)
2. 앱 로그 마지막 구간 — 바인딩 오류(`Address already in use`)나 설정 포트 불일치
3. `ufw status` — 리슨은 되는데 방화벽이 막는 경우(외부에서만 안 되는 증상)
4. `ss -tlnp` 의 바인딩 주소 — `127.0.0.1` 로만 열려 있으면 외부 접속이 안 된다

### 로그가 급증할 때의 임시 대응

1. `du -sh /var/log/agent-app/*` 와 `df -h /` 로 어느 파일이 얼마나 커졌는지 확인한다.
2. 크기가 자라는 파일은 삭제하지 않고 `: > 파일`(내용만 비움)로 줄인다. 앱이 파일을 열어 둔 채 쓰고 있어 `rm` 하면 공간이 반환되지 않는다.
3. 보존 대상 로그는 `log-retention.sh` 를 수동 실행해 7일 이상 된 것을 압축·이동한다.
4. 디스크 사용률은 `monitor.sh` 가 80% 초과 시 `[WARNING]` 으로 남기므로, 이 경고가 나오면 위 절차를 서버 관리자(agent-admin)가 수행한다.

### 다른 웹서버로 바꿀 때의 점검표

`monitor.sh` 는 환경변수로 대상을 바꾼다. 아래를 확인하고 설정한다.

| 점검 항목 | 확인할 것 | 설정 |
|---|---|---|
| 프로세스 이름 | `pgrep -a nginx`(예)로 실제 이름과 마스터/워커 구조 | `MONITOR_PROCESS=nginx` |
| 포트 | `ss -tlnp` 로 리슨 포트(80, 443 등) | `MONITOR_PORT=443` |
| 방화벽 | 새 포트를 UFW 가 허용하는지 | `ufw allow 443/tcp` |
| 임계값 | 웹서버의 평상시 CPU·MEM 분포를 먼저 측정해 `CPU_LIMIT`, `MEM_LIMIT`, `DISK_LIMIT` 조정(현재 20/10/80) | `monitor.sh` 상단 |
| 로그 위치와 크기 | 서버 자체 로그(`/var/log/nginx` 등)는 logrotate 로 회전, `monitor.log` 는 `MONITOR_LOG`, `MONITOR_MAX_BYTES`, `MONITOR_KEEP` | 환경변수 |
| 실행 권한 | cron 실행 계정이 대상 프로세스를 볼 수 있는지 | crontab 소유 계정 |

## 컨테이너라서 다르게 처리한 것

| 상황 | 처리 |
|---|---|
| systemd 가 없다 | `sshd -E /var/log/sshd_auth.log`, `service cron start` 로 직접 띄운다 |
| UFW 가 iptables 규칙을 바꾼다 | `--cap-add NET_ADMIN` (컨테이너 네트워크 네임스페이스 안에서만 적용, `--privileged` 는 쓰지 않음) |
| cron 이 사용자 작업을 건너뛴다 | 로그인 세션이 없어 실패하는 `pam_loginuid` 를 `/etc/pam.d/cron` 에서 끈다 |
| `TZ` 가 `su -` 로그인 셸에 전달되지 않는다 | `/etc/localtime` 을 Asia/Seoul 로 고정 |

실제 VM(iMac 의 Ubuntu VM 등)에서 수작업으로 할 때는 위 우회가 필요 없다.
`systemctl restart ssh`, `systemctl enable --now cron` 을 쓰면 된다.
