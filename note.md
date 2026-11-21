# b4-1 평가 대비 리포트

각 절은 "무엇을 했나 → 왜 그렇게 하나 → 어떻게 확인했나(근거 위치)" 순서다. 근거 로그는 `logs/` 에 있다.

---

## 1. SSH 포트 변경과 Root 원격 로그인 차단

### 무엇을 했나
`/etc/ssh/sshd_config` 에서 `Port 20022`, `PermitRootLogin no` 로 바꾸고 `sshd -t` 로 문법을 검사한 뒤 재시작했다.

### 왜 기본 보안인가
- **포트 변경**: 인터넷의 자동화 스캐너는 22번 포트에 무차별 대입을 쏟아낸다. 포트를 옮기면 이런 소음성 공격과
  인증 로그 폭주가 크게 줄어든다. 다만 포트 스캔으로 금방 찾을 수 있으므로 **그 자체로 방어가 아니라 노출을 줄이는
  보조 수단**이다. 진짜 방어는 키 인증, root 차단, 방화벽이다.
- **Root 차단**: `root` 는 모든 리눅스에 있는 계정 이름이라 공격자가 계정명을 추측할 필요가 없다. 뚫리면 곧바로 시스템
  전체 권한이다. 일반 계정으로 들어와 `sudo` 로 올리게 하면 (1) 공격자는 계정명과 비밀번호를 둘 다 알아야 하고
  (2) 누가 언제 권한을 올렸는지 기록이 남는다.
- `PermitRootLogin prohibit-password` 는 키로는 root 접속을 허용한다. 과제는 root 원격 로그인 자체를 막으라고 했으므로 `no` 다.

### 어떻게 확인했나
- 설정 파일 줄이 아니라 **실제 적용값**을 본다: `sshd -T | grep -E '^(port|permitrootlogin) '` → `port 20022`, `permitrootlogin no`
- 리슨: `ss -tulnp | grep sshd` → `0.0.0.0:20022`
- **실제 접속 비교**: 같은 공개키를 root 와 agent-admin 양쪽에 등록하고 20022 로 접속했다. agent-admin 은 성공,
  root 는 `Permission denied`. 조건이 같으므로 차이는 `PermitRootLogin` 뿐이다. 서버 인증 로그에
  `ROOT LOGIN REFUSED` 가 남는다. 22번은 `Connection refused`.
- 근거: `logs/01-ssh.log`, `logs/03-accounts.log` 의 "SSH 접속 검증"

---

## 2. 방화벽(UFW)

### 무엇을 했나
`ufw default deny incoming`, `ufw default allow outgoing`, `ufw allow 20022/tcp`, `ufw allow 15034/tcp`, `ufw enable`.

### 왜 이렇게 하나
- **기본 거부 + 필요한 것만 허용(화이트리스트)**: 새 서비스를 설치해 포트가 열려도 규칙을 추가하기 전에는 밖에서 닿지 않는다.
  반대로 "기본 허용 + 막을 것만 거부"는 모르는 포트가 열리는 순간 노출된다.
- 나가는 트래픽은 허용한다. 패키지 설치, 시간 동기화 같은 서버 자신의 요청이 막히지 않게 하기 위해서다.
- UFW 는 iptables/nftables 규칙을 만드는 프런트엔드다. 연결 추적(conntrack)으로 이미 맺어진 연결의 응답은 자동 허용되므로
  나간 요청의 응답이 들어오는 것은 막히지 않는다.
- `ufw allow` 는 IPv4 와 IPv6 규칙을 함께 만든다. 그래서 허용 줄이 4개(20022, 15034 × v4/v6)다.

### 어떻게 확인했나
- `ufw status verbose` → `Status: active`, `Default: deny (incoming), allow (outgoing)`, 허용 규칙 2종
- 체크리스트는 허용 줄이 정확히 4개이고 20022/15034 외 포트가 없는지 조회로 판정한다.
- 근거: `logs/02-firewall.log`

### 컨테이너에서의 차이
컨테이너는 자기 네트워크 네임스페이스를 갖는다. UFW 가 그 네임스페이스의 iptables 를 바꾸려면 `NET_ADMIN` 권한이 필요해서
`--cap-add NET_ADMIN` 을 줬다. 호스트 전체 권한(`--privileged`)은 주지 않았다.

---

## 3. 계정·그룹·권한과 ACL

### 무엇을 했나
| 계정 | 역할 | 그룹 |
|---|---|---|
| agent-admin | 운영/관리, 앱·cron 실행 | agent-common, agent-core |
| agent-dev | 개발, monitor.sh 작성 | agent-common, agent-core |
| agent-test | QA | agent-common |

| 경로 | 소유 | 모드 | ACL | 의도 |
|---|---|---|---|---|
| `$AGENT_HOME` | agent-admin:agent-common | 750 | - | 팀원만 들어올 수 있음 |
| `upload_files` | agent-admin:agent-common | 2770 | `group:agent-common:rwx` + 기본 ACL | 공유 디렉터리 |
| `api_keys` | agent-admin:agent-core | 2770 | `group:agent-core:rwx` + 기본 ACL | 보안 디렉터리 |
| `/var/log/agent-app` | agent-admin:agent-core | 2770 | `group:agent-core:rwx` + 기본 ACL | 운영 로그 |
| `$AGENT_HOME/bin` | agent-dev:agent-core | 2750 | - | 작성자만 수정, 운영은 실행 |

### 왜 공유/보안 디렉터리를 나누나
최소 권한 원칙이다. QA(agent-test)는 업로드 파일을 다뤄야 하지만 API 키와 운영 로그는 볼 필요가 없다.
키가 새면 외부 서비스 권한이 통째로 넘어가므로 접근 가능한 사람 수를 줄인다. 계정 하나가 뚫려도 피해 범위가 그 역할에 머문다.

### 개념
- **setgid 디렉터리(2xxx)**: 안에서 만든 파일의 그룹이 만든 사람의 기본 그룹이 아니라 **디렉터리의 그룹**이 된다.
  공유 디렉터리에서 "내가 만든 파일을 동료가 못 고치는" 문제를 막는다.
- **ACL**: 소유자·그룹·기타 3칸으로 표현할 수 없는 "특정 그룹에 추가 권한"을 준다. `getfacl` 의 `group:agent-core:rwx`.
- **mask**: 소유자 외 모든 ACL 항목의 **최대 권한 상한**이다. `mask::r-x` 면 `group:x:rwx` 도 실제로는 `r-x` 다.
  `chmod g-w` 가 mask 를 줄이므로 ACL 을 쓰는 디렉터리에서 chmod 는 조심해야 한다.
- **기본 ACL(`-d`)**: 디렉터리 안에 새로 생기는 파일·폴더가 물려받는 ACL. 이게 없으면 나중에 만든 파일에는 ACL 이 적용되지 않는다.
- **홈 디렉터리 750**: Ubuntu 22.04 는 홈을 750 으로 만든다. 다른 계정은 `/home/agent-admin` 을 통과하지 못해
  그 아래 `upload_files` 에도 닿지 못한다. `setfacl -m g:agent-common:--x` 로 **목록 조회 없이 통과만** 허용했다.

### 어떻게 확인했나
권한 표시를 읽는 데서 끝내지 않고 계정별로 실제 접근을 시도했다.
- agent-test: `upload_files` 쓰기 성공, `api_keys` 목록 `Permission denied`, 로그 디렉터리 쓰기 `Permission denied`
- agent-dev: `api_keys`, `/var/log/agent-app` 읽기/쓰기 성공
- 근거: `logs/03-accounts.log`

---

## 4. 환경 변수로 실행 환경 고정

### 무엇을 했나
`/etc/profile.d/agent-app.sh` 에 `AGENT_HOME`, `AGENT_PORT`, `AGENT_UPLOAD_DIR`, `AGENT_KEY_PATH`, `AGENT_LOG_DIR` 를 export 했다.

### 왜 환경 변수인가
- 경로·포트를 코드에 박지 않으면 같은 바이너리를 개발·운영 서버에서 설정만 바꿔 쓸 수 있다(12-Factor 의 설정 분리).
- 앱이 부트 시 필수 값이 없으면 바로 실패한다. 잘못된 설정으로 반쯤 동작하는 상태를 만들지 않는다(fail fast).
- `profile.d` 는 모든 로그인 셸이 읽는다. `.bashrc` 는 대화형 비로그인 셸용이라 `su -` 나 SSH 로그인과 동작이 다르다.

### 주의: cron 에는 이 변수가 없다
cron 은 로그인 셸이 아니라서 `profile.d` 를 읽지 않고 PATH 도 `/usr/bin:/bin` 뿐이다.
그래서 `monitor.sh` 가 시작할 때 `AGENT_HOME` 이 비어 있으면 `/etc/profile.d/agent-app.sh` 를 직접 읽고 PATH 를 스스로 정한다.

### 제공 앱과 문서의 차이
과제 문서의 `AGENT_KEY_PATH=$AGENT_HOME/api_keys/t_secret.key` 로 실행하면 앱이
`Key Path Mismatch. Expected: /home/agent-admin/agent-app/api_keys` 로 실패했다. 디렉터리로 바꾸자
`Missing File: secret.key` 가 나왔다. 앱 요구대로 디렉터리 경로와 `secret.key` 를 쓰고, 문서가 요구한 `t_secret.key` 도 같은 내용으로 두었다.

### 어떻게 확인했나
- `su - agent-admin -c 'env | grep ^AGENT_'`
- root 실행: `[1/5] Checking User Account [FAIL] Running as 'root' is forbidden.`
- agent-admin 실행: 5단계 `[OK]`, `Agent READY`, `ss -tlnp` 에 `0.0.0.0:15034`, `ps -o user` 가 agent-admin
- 근거: `logs/04-app.log`

---

## 5. monitor.sh

### 수집 방법과 원리
- **CPU 사용률**: `/proc/stat` 첫 줄은 부팅 이후 누적 CPU 시간(user, nice, system, idle, iowait, irq, softirq, steal)이다.
  누적값이라 한 번 읽어서는 "지금" 사용률을 알 수 없다. 1초 간격으로 두 번 읽어 차이를 낸다.
  `사용률 = (전체 증가분 - (idle + iowait) 증가분) / 전체 증가분 × 100`
- **메모리 사용률**: `(MemTotal - MemAvailable) / MemTotal`. `MemFree` 로 계산하면 커널이 캐시로 쓰는 메모리까지
  "사용 중"으로 잡혀 과장된다. `MemAvailable` 은 캐시처럼 곧 회수할 수 있는 양을 포함한다.
- **디스크**: `df -P /` 의 Use%. `-P` 는 긴 장치 이름 때문에 줄이 나뉘지 않게 POSIX 형식으로 고정한다.

### 헬스체크와 종료 코드
- 프로세스가 없거나 15034 가 리슨이 아니면 `[FAIL]` 을 출력하고 **exit 1**. 이 둘은 서비스가 죽은 것이므로
  자원 수치를 기록할 의미가 없다. cron·상위 감시 도구는 종료 코드로 실패를 판단한다.
- 방화벽 비활성과 임계값 초과는 **경고만** 한다. 서비스는 동작 중이므로 기록을 계속 남기는 것이 더 중요하다.
- 제공 앱은 PyInstaller 로 묶여 부트로더(부모)와 워커(자식)가 같은 이름으로 뜬다. `pgrep -n -x` 로 가장 최근의 워커를 쓴다.
  `-x` 는 이름 완전 일치다. `-f` 로 찾으면 경로에 `agent-app` 이 들어간 monitor.sh 자신까지 잡힌다.

### agent-admin 이 방화벽 상태를 보는 방법
`ufw status` 는 root 권한이 필요하다. sudoers 에 `agent-admin ALL=(root) NOPASSWD: /usr/sbin/ufw status` **한 줄만** 허용했다.
`ufw` 전체나 `ALL` 을 주면 방화벽을 끌 수도 있게 된다. sudo 가 안 되는 계정은 `/etc/ufw/ufw.conf` 의 `ENABLED=yes` 로 대신 판단한다.

### 로그 용량 관리
- 10MB 가 넘으면 `monitor.log → .1 → .2 … → .9` 로 밀고 가장 오래된 것을 지운다. 현재 파일 포함 10개.
- 운영값으로는 재현에 오래 걸려서, 같은 로직을 `MONITOR_MAX_BYTES=300 MONITOR_KEEP=4` 로 낮춰 실제로 회전하는지 확인했다.
- `flock -n` 으로 이전 회차가 끝나지 않았으면 이번 회차를 건너뛴다. 매분 실행이 겹치면 로그 줄이 섞이기 때문이다.
- 로그 보존이 필요한 이유: 로그가 디스크를 채우면 앱이 쓰기 실패로 멈추고, 같은 파티션을 쓰는 다른 서비스까지 장애가 난다.

### 어떻게 확인했나
정상, 권한 없는 계정(agent-test) 실행 거부, 프로세스 없음(exit 1), 포트 없음(exit 1), 방화벽 off(`[WARNING]` 후 exit 0),
메모리 임계값 초과 경고, 로그 회전을 모두 실행했다. 근거: `logs/05-monitor.log`

---

## 6. cron

### 무엇을 했나
agent-admin 의 crontab:
```
* * * * * /home/agent-admin/agent-app/bin/monitor.sh > /dev/null 2>> /var/log/agent-app/monitor-cron.err
10 3 * * * /home/agent-admin/agent-app/bin/log-retention.sh >> /var/log/agent-app/retention.out 2>&1
```

### 설명
- 다섯 필드는 분·시·일·월·요일이다. `* * * * *` 는 매분.
- cron 실행 계정을 agent-admin 으로 둔 이유: 로그 디렉터리와 monitor.sh 에 agent-core 권한만 있으면 되고 root 가 필요 없다.
- 콘솔 출력은 버리고 오류만 파일에 남긴다. monitor.log 는 스크립트가 직접 쓴다. cron 의 표준 출력을 그대로 두면 메일 전송을 시도하거나 버려진다.
- 컨테이너에는 로그인 세션이 없어 cron 의 PAM `pam_loginuid` 가 실패하고 사용자 작업을 건너뛴다. `/etc/pam.d/cron` 에서 그 줄을 껐다.

### 어떻게 확인했나
등록 직후 `wc -l` 과 125초 뒤 `wc -l` 을 비교해 cron 이 추가한 줄 수를 기록했다(2줄). 근거: `logs/06-cron.log`

---

## 7. 보너스

### report.sh
monitor.log 의 `CPU:` `MEM:` `DISK_USED:` 값을 awk 로 모아 평균·최대(시각)·최소(시각)·표본 수를 낸다.
로그 시각이 `YYYY-MM-DD HH:MM:SS` 고정 폭이라 **문자열 비교가 곧 시간 비교**여서 시작·종료 구간 필터가 간단하다.

### log-retention.sh
- `find -mtime +6` = 7일 이상 경과(24시간 단위로 내림하므로 +6 이 "7일 이상")
- 압축본은 `touch -r` 로 원본 수정 시각을 물려받는다. 그래야 30일 삭제 판단이 압축한 날이 아니라 원래 로그 날짜를 기준으로 한다.
- 디렉터리 없음, 권한 없음, 대상 0개는 `[WARNING]`/`[INFO]` 후 exit 0. 매일 도는 작업이 한 번 실패로 cron 오류를 쌓지 않게 한다.
- 근거: `logs/07-bonus.log` (8일 전 로그 → 아카이브 압축, 31일 전 아카이브 → 삭제, 3일 전 로그 → 유지)

---

## 8. 예상 질문과 답

**Q. 포트를 바꾸면 안전해지나?**
노출이 줄 뿐 안전해지지는 않는다. 포트 스캔으로 찾을 수 있다. 실질 방어는 root 차단, 키 인증, 방화벽의 출발지 제한이다.

**Q. ufw 규칙이 들어갔는지 어떻게 확신하나?**
`ufw status verbose` 에서 active 와 기본 정책, 허용 규칙을 본다. 체크리스트는 허용 줄 수와 포트 목록을 조회로 판정한다.
SSH 는 20022 접속 성공과 22 거부로 실제 동작까지 확인했다.

**Q. ACL 없이 chmod 만으로는 안 되나?**
그룹이 하나면 된다. 하지만 소유 그룹 외에 다른 그룹에도 권한을 줘야 하거나, 새로 생기는 파일에도 같은 그룹 권한을
물려줘야 하면 기본 ACL 이 필요하다. 이번에는 setgid 로 그룹 상속, 기본 ACL 로 권한 상속을 함께 썼다.

**Q. monitor.sh 의 CPU 값이 top 과 다르다.**
top 은 기본 3초(또는 지정 간격) 동안의 값이고 monitor.sh 는 1초 구간이다. 둘 다 /proc/stat 차이 방식이라 구간이 다르면 값이 다르다.

**Q. 헬스체크 실패와 경고를 왜 다르게 처리했나?**
프로세스·포트 실패는 서비스 불능이라 즉시 알리고 멈춰야 한다(exit 1). 방화벽·자원 경고는 서비스는 살아 있으므로
기록을 이어가며 사람이 판단할 정보로 남긴다.

**Q. 매분 cron 이 겹치면?**
`flock -n` 으로 이미 실행 중이면 이번 회차를 건너뛴다.

**Q. 로그를 왜 크기와 시간 두 기준으로 관리하나?**
크기 기준(10MB/10개)은 폭주 시 디스크를 지키고, 시간 기준(7일 압축/30일 삭제)은 보존 기간 정책을 지킨다.
평소에는 시간 기준이, 장애로 로그가 폭증할 때는 크기 기준이 먼저 작동한다.

## 9. 근거 위치

| 내용 | 파일 |
|---|---|
| 체크리스트 판정 | `logs/00-checklist.log` |
| SSH | `logs/01-ssh.log`, `logs/03-accounts.log` |
| 방화벽 | `logs/02-firewall.log` |
| 계정·권한·ACL | `logs/03-accounts.log` |
| 앱 실행 | `logs/04-app.log` |
| monitor.sh | `logs/05-monitor.log`, `agent/monitor.sh` |
| cron | `logs/06-cron.log` |
| 보너스 | `logs/07-bonus.log`, `agent/report.sh`, `agent/log-retention.sh` |
| 수행 내역서 | `docs/report.md` |
