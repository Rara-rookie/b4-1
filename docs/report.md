# b4-1 요구사항 수행 내역서

- 생성: 2026-09-15 13:43:51 KST (scripts/make-report.sh)
- 환경: 실행 시각: 2026-09-15 13:37:26 KST  호스트: agent-server  커널: 5.15.167.4-microsoft-standard-WSL2
- 원본 증거: `logs/` 아래 단계별 로그. 이 문서의 모든 출력은 그 로그에서 그대로 발췌했다.

## 0. 필수 증거 체크리스트

실제 상태를 다시 조회해 판정한 결과다(logs/00-checklist.log).

```text
[PASS] SSH 포트 20022 리슨, PermitRootLogin no
[PASS] root SSH 접속 거부 기록
[PASS] UFW 활성, 허용 규칙은 20022/tcp·15034/tcp 뿐
[PASS] 계정 3개와 그룹 소속
[PASS] upload_files=agent-common rwx, api_keys·로그=agent-core rwx
[PASS] agent-test 는 api_keys 접근 불가
[PASS] Boot Sequence 5단계 [OK] 와 Agent READY
[PASS] 앱이 0.0.0.0:15034 LISTEN, 실행 계정 agent-admin
[PASS] monitor.sh 위치/소유/권한
[PASS] monitor.log 형식
[PASS] agent-admin crontab 매분 등록
[PASS] cron 자동 실행으로 로그 증가
```

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

```text
$ sed -i -E 's/^#?Port .*/Port 20022/; s/^#?PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
$ grep -nE '^(Port|PermitRootLogin) ' /etc/ssh/sshd_config
14:Port 20022
33:PermitRootLogin no
$ sshd -T | grep -E '^(port|permitrootlogin) '
port 20022
permitrootlogin no
$ ss -tulnp | grep sshd
tcp   LISTEN 0      128          0.0.0.0:20022      0.0.0.0:*    users:(("sshd",pid=70,fd=4))
tcp   LISTEN 0      128             [::]:20022         [::]:*    users:(("sshd",pid=70,fd=5))
# root 원격 로그인 거부는 계정 생성 뒤 03 단계에서 실제 접속으로 검증한다.
```

같은 공개키를 root 와 agent-admin 에 등록하고 20022 로 접속했다. 결과가 갈리는 이유는 PermitRootLogin 뿐이다.

```text
$ ssh -i /root/.ssh/id_b41 -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -p 20022 agent-admin@127.0.0.1 'echo login-ok: $(whoami)@$(hostname)'
login-ok: agent-admin@agent-server

$ ssh -i /root/.ssh/id_b41 -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -p 20022 root@127.0.0.1 'echo root-login-should-not-happen'
root@127.0.0.1: Permission denied (publickey,password).
(exit 255)

$ ssh -i /root/.ssh/id_b41 -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=3 -p 22 agent-admin@127.0.0.1 true
ssh: connect to host 127.0.0.1 port 22: Connection refused
(exit 255)

$ grep -E 'ROOT LOGIN REFUSED|Accepted publickey' /var/log/sshd_auth.log | tail -4
Accepted publickey for agent-admin from 127.0.0.1 port 56392 ssh2: ED25519 SHA256:AudRTtdooQDentuoV6pFlTGm4FB/EmBD1vyn0brglww
ROOT LOGIN REFUSED FROM 127.0.0.1 port 56408
ROOT LOGIN REFUSED FROM 127.0.0.1 port 56408 [preauth]
```

### 1-2. 방화벽(UFW)

```text
$ ufw default deny incoming
Default incoming policy changed to 'deny'
(be sure to update your rules accordingly)
$ ufw allow 20022/tcp comment 'SSH'
Rules updated
Rules updated (v6)
$ ufw allow 15034/tcp comment 'AGENT APP'
Rules updated
Rules updated (v6)
$ ufw status verbose
Status: active
Logging: on (low)
Default: deny (incoming), allow (outgoing), deny (routed)
New profiles: skip

To                         Action      From
--                         ------      ----
20022/tcp                  ALLOW IN    Anywhere                   # SSH
15034/tcp                  ALLOW IN    Anywhere                   # AGENT APP
20022/tcp (v6)             ALLOW IN    Anywhere (v6)              # SSH
15034/tcp (v6)             ALLOW IN    Anywhere (v6)              # AGENT APP
```

## 2. 계정/그룹/권한 체계

### 2-1. 계정과 그룹

```text
$ id agent-admin; id agent-dev; id agent-test
uid=1000(agent-admin) gid=1002(agent-admin) groups=1002(agent-admin),1000(agent-common),1001(agent-core)
uid=1001(agent-dev) gid=1003(agent-dev) groups=1003(agent-dev),1000(agent-common),1001(agent-core)
uid=1002(agent-test) gid=1004(agent-test) groups=1004(agent-test),1000(agent-common)
$ getent group agent-common agent-core
agent-common:x:1000:agent-admin,agent-dev,agent-test
agent-core:x:1001:agent-admin,agent-dev
```

### 2-2. 디렉터리 구조와 권한(ACL)

```text
$ ls -ld /home/agent-admin /home/agent-admin/agent-app /home/agent-admin/agent-app/upload_files /home/agent-admin/agent-app/api_keys /home/agent-admin/agent-app/bin /var/log/agent-app
drwxr-x---+ 3 agent-admin agent-admin  4096 Sep 15 13:37 /home/agent-admin
drwxr-x---  5 agent-admin agent-common 4096 Sep 15 13:37 /home/agent-admin/agent-app
drwxrws---+ 2 agent-admin agent-core   4096 Sep 15 13:37 /home/agent-admin/agent-app/api_keys
drwxr-s---  2 agent-dev   agent-core   4096 Sep 15 13:37 /home/agent-admin/agent-app/bin
drwxrws---+ 2 agent-admin agent-common 4096 Sep 15 13:37 /home/agent-admin/agent-app/upload_files
drwxrws---+ 2 agent-admin agent-core   4096 Sep 15 13:37 /var/log/agent-app
$ getfacl -p /home/agent-admin/agent-app/upload_files /home/agent-admin/agent-app/api_keys /var/log/agent-app
# file: /home/agent-admin/agent-app/upload_files
# owner: agent-admin
# group: agent-common
# flags: -s-
user::rwx
group::rwx
group:agent-common:rwx
mask::rwx
other::---
default:user::rwx
default:group::rwx
default:group:agent-common:rwx
default:mask::rwx
default:other::---

# file: /home/agent-admin/agent-app/api_keys
# owner: agent-admin
# group: agent-core
# flags: -s-
user::rwx
group::rwx
group:agent-core:rwx
mask::rwx
other::---
default:user::rwx
default:group::rwx
default:group:agent-core:rwx
default:mask::rwx
default:other::---

# file: /var/log/agent-app
# owner: agent-admin
# group: agent-core
# flags: -s-
user::rwx
group::rwx
group:agent-core:rwx
mask::rwx
other::---
```

계정별로 실제 접근을 시도한 결과다(Permission denied 가 정책대로 막힌 것).

```text
## 확인: 계정별 실제 접근

agent-test$ touch /home/agent-admin/agent-app/upload_files/from-agent-test.txt && ls -l /home/agent-admin/agent-app/upload_files/from-agent-test.txt
-rw-rw----+ 1 agent-test agent-common 0 Sep 15 13:37 /home/agent-admin/agent-app/upload_files/from-agent-test.txt

agent-dev$ touch /home/agent-admin/agent-app/upload_files/from-agent-dev.txt && ls -l /home/agent-admin/agent-app/upload_files/from-agent-dev.txt
-rw-rw----+ 1 agent-dev agent-common 0 Sep 15 13:37 /home/agent-admin/agent-app/upload_files/from-agent-dev.txt
# agent-test 는 보안 디렉터리에 접근할 수 없어야 한다(Permission denied 가 정상).

agent-test$ ls /home/agent-admin/agent-app/api_keys
ls: cannot open directory '/home/agent-admin/agent-app/api_keys': Permission denied
(exit 2)

agent-test$ touch /var/log/agent-app/agent-test-probe.log
touch: cannot touch '/var/log/agent-app/agent-test-probe.log': Permission denied
(exit 1)

agent-dev$ touch /home/agent-admin/agent-app/api_keys/.probe && rm /home/agent-admin/agent-app/api_keys/.probe && echo 'agent-dev: api_keys 읽기/쓰기 가능'
agent-dev: api_keys 읽기/쓰기 가능

agent-dev$ touch /var/log/agent-app/.probe && rm /var/log/agent-app/.probe && echo 'agent-dev: /var/log/agent-app 읽기/쓰기 가능'
agent-dev: /var/log/agent-app 읽기/쓰기 가능
```

## 3. 애플리케이션 실행 환경

```text
$ cat /etc/profile.d/agent-app.sh
# /etc/profile.d/agent-app.sh 로 설치한다. 로그인 셸과 monitor.sh 가 같은 값을 쓴다.
#
# AGENT_KEY_PATH: 과제 문서는 "$AGENT_HOME/api_keys/t_secret.key" 로 적었지만, 제공 앱은
# 디렉터리 경로를 기대하고(Key Path Mismatch. Expected: .../api_keys) 그 안의 secret.key 를 읽는다.
# 실측 결과를 따른다. 근거: logs/04-app.log
export AGENT_HOME=/home/agent-admin/agent-app
export AGENT_PORT=15034
export AGENT_UPLOAD_DIR=$AGENT_HOME/upload_files
export AGENT_KEY_PATH=$AGENT_HOME/api_keys
agent-admin$ env | grep '^AGENT_' | sort
AGENT_HOME=/home/agent-admin/agent-app
AGENT_KEY_PATH=/home/agent-admin/agent-app/api_keys
AGENT_LOG_DIR=/var/log/agent-app
AGENT_PORT=15034
AGENT_UPLOAD_DIR=/home/agent-admin/agent-app/upload_files
$ ls -l /home/agent-admin/agent-app/api_keys && cat /home/agent-admin/agent-app/api_keys/t_secret.key
total 8
-rw-r-----+ 1 agent-admin agent-core 19 Sep 15 13:37 secret.key
-rw-r-----+ 1 agent-admin agent-core 19 Sep 15 13:37 t_secret.key
agent_api_key_test
```

> 과제 문서는 `AGENT_KEY_PATH=$AGENT_HOME/api_keys/t_secret.key` 로 적었지만, 제공 앱은 디렉터리 경로를 요구하고(`Key Path Mismatch. Expected: .../api_keys`) 그 안의 `secret.key` 를 읽었다. 실측에 맞춰 디렉터리를 지정하고 두 파일명을 같은 내용으로 두었다.

root 실행 거부와 일반 계정 실행 결과:

```text
## root 로 실행하면 거부된다

$ cd /home/agent-admin/agent-app && timeout 5 ./agent-app 2>&1 | head -4
>>> Starting Agent Boot Sequence...
[1/5] Checking User Account               [FAIL]
   >>> Error: Running as 'root' is forbidden.
[2/5] Verifying Environment Variables     [FAIL]
$ sed -n '1,/Agent READY/p' /home/agent-admin/agent-app/agent-app.out
>>> Starting Agent Boot Sequence...
[1/5] Checking User Account               [OK]
   ... Running as service user 'agent-admin' (uid=1000)
[2/5] Verifying Environment Variables     [OK]
   ... All required Envs correct
[3/5] Checking Required Files             [OK]
   ... Verified 'secret.key' with correct key string.
[4/5] Checking Port Availability          [OK]
   ... Port 15034 is available.
[5/5] Verifying Log Permission            [OK]
   ... Log directory is writable: /var/log/agent-app
------------------------------------------------------------
All Boot Checks Passed!
Agent READY
$ ss -tlnp | grep ':15034'
LISTEN 0      1            0.0.0.0:15034      0.0.0.0:*                                
$ ps -o user,pid,ppid,pcpu,rss,args -C agent-app
USER         PID    PPID %CPU   RSS COMMAND
agent-a+     644       1  2.0  1088 ./agent-app
agent-a+     648     644 19.3 65640 ./agent-app
```

## 4. monitor.sh

### 배치 정책과 실행

```text
$ stat -c '%U:%G %a %n' /home/agent-admin/agent-app/bin/*.sh
agent-dev:agent-core 750 /home/agent-admin/agent-app/bin/log-retention.sh
agent-dev:agent-core 750 /home/agent-admin/agent-app/bin/monitor.sh
agent-dev:agent-core 750 /home/agent-admin/agent-app/bin/report.sh
$ cat /etc/sudoers.d/agent-monitor && visudo -cf /etc/sudoers.d/agent-monitor
agent-admin ALL=(root) NOPASSWD: /usr/sbin/ufw status
/etc/sudoers.d/agent-monitor: parsed OK
## 정상 실행(cron 실행 계정 agent-admin)

agent-admin$ $AGENT_HOME/bin/monitor.sh; echo "exit=$?"
====== SYSTEM MONITOR RESULT ======

[HEALTH CHECK]
Checking process 'agent-app'... [OK] (PID: 648)
Checking port 15034... [OK]

[STATUS CHECK]
Firewall (ufw) : active

[RESOURCE MONITORING]
CPU Usage : 1.3%
MEM Usage : 9.7%
DISK Used : 1%


====== STATISTICS REPORT ======
[CPU]
Average : 1.3%
Maximum : 1.3% at 2026-09-15 13:37:36
Minimum : 1.3% at 2026-09-15 13:37:36
[Memory]
Average : 9.7%
Maximum : 9.7% at 2026-09-15 13:37:36
Minimum : 9.7% at 2026-09-15 13:37:36
[Samples]
Data Points: 1 samples

[INFO] Log appended: /var/log/agent-app/monitor.log
exit=0

agent-admin$ $AGENT_HOME/bin/monitor.sh > /dev/null; $AGENT_HOME/bin/monitor.sh > /dev/null; tail -3 $AGENT_LOG_DIR/monitor.log
[2026-09-15 13:37:36] PID:648 CPU:1.3% MEM:9.7% DISK_USED:1%
[2026-09-15 13:37:37] PID:648 CPU:1.1% MEM:10.0% DISK_USED:1%
```

### 실패·경고 경로

```text
## Health Check 실패 시 exit 1

agent-admin$ MONITOR_PROCESS=no-such-app $AGENT_HOME/bin/monitor.sh; echo "exit=$?"
====== SYSTEM MONITOR RESULT ======

[HEALTH CHECK]
Checking process 'no-such-app'... [FAIL]
exit=1

agent-admin$ MONITOR_PORT=15999 $AGENT_HOME/bin/monitor.sh; echo "exit=$?"
====== SYSTEM MONITOR RESULT ======

[HEALTH CHECK]
Checking process 'agent-app'... [OK] (PID: 648)
Checking port 15999... [FAIL]
exit=1

$ tail -2 /var/log/agent-app/monitor.log
[2026-09-15 13:37:38] [ERROR] process 'no-such-app' is not running
[2026-09-15 13:37:38] [ERROR] port 15999 is not listening (PID:648)
## 방화벽 비활성: [WARNING] 만 출력하고 계속 진행

$ ufw disable
Firewall stopped and disabled on system startup

agent-admin$ $AGENT_HOME/bin/monitor.sh | sed -n "/STATUS CHECK/,/INFO/p"; echo "exit=${PIPESTATUS[0]}"
[STATUS CHECK]
Firewall (ufw) : inactive

[RESOURCE MONITORING]
CPU Usage : 1.4%
MEM Usage : 10.5%
DISK Used : 1%

[WARNING] Firewall is not active
[WARNING] MEM threshold exceeded (10.5% > 10%)
## 권한 없는 계정(agent-test)은 실행할 수 없다

agent-test$ $AGENT_HOME/bin/monitor.sh; echo "exit=$?"
-bash: line 1: /home/agent-admin/agent-app/bin/monitor.sh: Permission denied
exit=126
```

### 로그 용량 관리

운영값은 10MB/10개다. 같은 로직을 300바이트/4개로 낮춰 회전이 실제로 일어나는지 확인했다.

```text
## 로그 용량 관리: 한도를 300바이트, 보관 4개로 낮춰 회전을 재현(운영값 10MB/10개)

agent-admin$ rm -rf /tmp/rotate-demo && mkdir -p /tmp/rotate-demo && for i in $(seq 1 12); do MONITOR_LOG=/tmp/rotate-demo/monitor.log MONITOR_MAX_BYTES=300 MONITOR_KEEP=4 $AGENT_HOME/bin/monitor.sh | grep rotated; done; ls -l /tmp/rotate-demo
[INFO] Log rotated: /tmp/rotate-demo/monitor.log (310 bytes >= 300)
[INFO] Log rotated: /tmp/rotate-demo/monitor.log (310 bytes >= 300)
total 12
-rw-rw---- 1 agent-admin agent-admin 124 Sep 15 13:37 monitor.log
-rw-rw---- 1 agent-admin agent-admin 310 Sep 15 13:37 monitor.log.1
-rw-rw---- 1 agent-admin agent-admin 310 Sep 15 13:37 monitor.log.2
```

## 5. 자동 실행(cron)

```text
## agent-admin crontab 등록

$ crontab -u agent-admin /tmp/agent-admin.cron && crontab -l -u agent-admin
# 매분 상태 점검. 콘솔 출력은 버리고 오류만 남긴다(monitor.log 에는 스크립트가 직접 쓴다).
* * * * * /home/agent-admin/agent-app/bin/monitor.sh > /dev/null 2>> /var/log/agent-app/monitor-cron.err
# 매일 03:10 로그 보존 정책(보너스 2)
10 3 * * * /home/agent-admin/agent-app/bin/log-retention.sh >> /var/log/agent-app/retention.out 2>&1
## 자동 실행 확인: 등록 직후와 2분 뒤 줄 수 비교

$ date '+%F %T'; wc -l /var/log/agent-app/monitor.log; tail -2 /var/log/agent-app/monitor.log
2026-09-15 13:37:57
6 /var/log/agent-app/monitor.log
[2026-09-15 13:37:38] [ERROR] port 15999 is not listening (PID:648)
[2026-09-15 13:37:43] PID:648 CPU:1.4% MEM:10.5% DISK_USED:1%
# 분 경계를 두 번 넘길 때까지 기다린다(약 125초).

$ date '+%F %T'; wc -l /var/log/agent-app/monitor.log; tail -4 /var/log/agent-app/monitor.log
2026-09-15 13:40:02
8 /var/log/agent-app/monitor.log
[2026-09-15 13:37:38] [ERROR] port 15999 is not listening (PID:648)
[2026-09-15 13:37:43] PID:648 CPU:1.4% MEM:10.5% DISK_USED:1%
[2026-09-15 13:38:03] PID:648 CPU:3.1% MEM:10.2% DISK_USED:1%
[2026-09-15 13:39:02] PID:648 CPU:2.9% MEM:12.8% DISK_USED:1%
# cron 이 추가한 줄: 2줄 (기대: 2줄 이상)

$ cat /var/log/agent-app/monitor-cron.err 2>/dev/null || echo '(cron 오류 없음)'
```

## 6. 보너스

### 보너스 1: report.sh

```text
## 보너스 1: 전체 구간 통계

agent-admin$ $AGENT_HOME/bin/report.sh
  ====== STATISTICS REPORT ======
  Range : 2026-09-15 13:37:36 ~ 2026-09-15 13:39:02
  [CPU]
    Average : 1.9%
    Maximum : 3.1% at 2026-09-15 13:38:03
    Minimum : 1.1% at 2026-09-15 13:37:37
  [Memory]
    Average : 10.5%
    Maximum : 12.8% at 2026-09-15 13:39:02
    Minimum : 9.7% at 2026-09-15 13:37:36
  [Disk]
    Average : 1.0%
    Maximum : 1.0% at 2026-09-15 13:37:36
    Minimum : 1.0% at 2026-09-15 13:37:36
  [Samples]
    Data Points: 6 samples
```

### 보너스 2: 시간 기반 보존 정책

```text
## 보너스 2: 날짜를 되돌린 파일로 7일/30일 규칙 재현

$ ls -l --time-style=+%F /var/log/agent-app /var/log/monitor/agent-app/archive
/var/log/agent-app:
total 20
-rw-rw----+ 1 agent-admin agent-core 7389 2026-09-15 agent_app.log
-rw-rw----+ 1 agent-admin agent-core    0 2026-09-15 monitor-cron.err
-rw-rw----+ 1 agent-admin agent-core  506 2026-09-15 monitor.log
-rw-rw----+ 1 agent-admin agent-core    9 2026-09-07 old-worker.log
-rw-rw----+ 1 agent-admin agent-core   12 2026-09-12 recent-worker.log

/var/log/monitor/agent-app/archive:
total 4
-rw-r--r-- 1 agent-admin agent-core 28 2026-08-15 ancient.log.20260801.gz

agent-admin$ $AGENT_HOME/bin/log-retention.sh
[2026-09-15 13:40:02] [ARCHIVE] /var/log/agent-app/old-worker.log -> /var/log/monitor/agent-app/archive/old-worker.log.20260907.gz
[2026-09-15 13:40:02] [DELETE] /var/log/monitor/agent-app/archive/ancient.log.20260801.gz
[2026-09-15 13:40:02] [DONE] 압축 1건, 삭제 1건

$ ls -l --time-style=+%F /var/log/agent-app /var/log/monitor/agent-app/archive
/var/log/agent-app:
total 16
-rw-rw----+ 1 agent-admin agent-core 7389 2026-09-15 agent_app.log
-rw-rw----+ 1 agent-admin agent-core    0 2026-09-15 monitor-cron.err
-rw-rw----+ 1 agent-admin agent-core  506 2026-09-15 monitor.log
-rw-rw----+ 1 agent-admin agent-core   12 2026-09-12 recent-worker.log

/var/log/monitor/agent-app/archive:
total 4
## 보너스 2 예외 처리

agent-admin$ $AGENT_HOME/bin/log-retention.sh
[2026-09-15 13:40:02] [INFO] 7일 이상 지난 로그가 없다.
[2026-09-15 13:40:02] [INFO] 30일 이상 지난 아카이브가 없다.
[2026-09-15 13:40:02] [DONE] 압축 0건, 삭제 0건

agent-admin$ LOG_SRC=/var/log/no-such-dir $AGENT_HOME/bin/log-retention.sh; echo "exit=$?"
[2026-09-15 13:40:02] [WARNING] 원본 로그 디렉터리가 없다: /var/log/no-such-dir (건너뜀)
exit=0

agent-test$ bash /tmp/log-retention-test.sh; echo "exit=$?"
[2026-09-15 13:40:02] [WARNING] 아카이브 디렉터리를 만들거나 쓸 권한이 없다: /var/log/monitor/agent-app/archive (건너뜀)
exit=0
```
