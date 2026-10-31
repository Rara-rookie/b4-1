#!/usr/bin/env bash
# b4-1 실습 환경을 한 번에 만들고 과제 전 과정을 실행한다.
#
#   ./setup.sh           Ubuntu 22.04 컨테이너를 새로 만들고 1~7단계 실행, 증거는 logs/ 로 모은다
#   ./setup.sh shell     만들어 둔 서버에 root 셸로 들어간다
#   ./setup.sh ssh       호스트에서 20022 로 agent-admin 접속(키는 컨테이너에서 꺼내 쓴다)
#   ./setup.sh clean     컨테이너를 지운다
#
# 필요한 것: Docker(Desktop) 실행 중, 이 폴더의 agent-app.zip(제공 앱)
# 호스트 포트가 이미 쓰이고 있으면: HOST_SSH_PORT=21022 HOST_APP_PORT=25034 ./setup.sh
set -euo pipefail

# Windows Git Bash 는 /opt 같은 인자를 C:/Program Files/Git/opt 로 바꾼다. macOS·Linux 에서는 의미 없다.
export MSYS_NO_PATHCONV=1
HERE=$(cd "$(dirname "$0")" && { pwd -W 2>/dev/null || pwd; })

IMAGE=codyssey-b4-1:ubuntu22.04
NAME=b4-1-server
HOST_SSH_PORT=${HOST_SSH_PORT:-20022}
HOST_APP_PORT=${HOST_APP_PORT:-15034}
APP_ZIP=${APP_ZIP:-$HERE/agent-app.zip}

die() { echo "[ERROR] $*" >&2; exit 1; }

case "${1:-up}" in
    shell) exec docker exec -it "$NAME" bash ;;
    clean) docker rm -f "$NAME"; exit 0 ;;
    ssh)
        docker cp "$NAME:/root/.ssh/id_b41" "$HERE/.id_b41" && chmod 600 "$HERE/.id_b41"
        exec ssh -i "$HERE/.id_b41" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                 -p "$HOST_SSH_PORT" agent-admin@127.0.0.1 ;;
    up) ;;
    *) die "알 수 없는 명령: $1 (up | shell | ssh | clean)" ;;
esac

command -v docker >/dev/null 2>&1 || die "docker 가 없다. Docker Desktop 을 설치할 것"
docker info >/dev/null 2>&1 || die "Docker 엔진이 꺼져 있다. Docker Desktop 을 실행할 것"
[ -f "$APP_ZIP" ] || die "제공 앱이 없다: $APP_ZIP"

echo "[1/5] 이미지 빌드 ($IMAGE)"
docker build -t "$IMAGE" "$HERE/env"

echo "[2/5] 서버 컨테이너 생성 ($NAME)"
docker rm -f "$NAME" >/dev/null 2>&1 || true
# ufw 가 iptables 규칙을 바꾸려면 NET_ADMIN 권한이 필요하다. --privileged 까지는 주지 않는다.
docker run -d --init --name "$NAME" --hostname agent-server \
    --cap-add NET_ADMIN --cap-add NET_RAW \
    -p "$HOST_SSH_PORT:20022" -p "$HOST_APP_PORT:15034" \
    "$IMAGE" sleep infinity >/dev/null

echo "[3/5] 스크립트와 제공 앱 복사"
docker exec "$NAME" mkdir -p /opt/b4-1
docker cp "$HERE/scripts" "$NAME:/opt/b4-1/"
docker cp "$HERE/agent" "$NAME:/opt/b4-1/"
docker cp "$APP_ZIP" "$NAME:/opt/b4-1/agent-app.zip"
# Windows 에서 체크아웃하면 줄 끝이 CRLF 로 바뀌어 bash 가 실행하지 못한다.
docker exec "$NAME" bash -c "find /opt/b4-1 -type f \( -name '*.sh' -o -name '*.env' \) -exec sed -i 's/\r$//' {} +"

echo "[4/5] 과제 단계 실행(약 3분, cron 확인 대기 포함)"
docker exec "$NAME" bash /opt/b4-1/scripts/run-all.sh

echo "[5/5] 수행 내역서 생성, 증거 로그 수집 -> docs/report.md, logs/"
docker exec "$NAME" bash /opt/b4-1/scripts/make-report.sh
rm -rf "$HERE/logs"
docker cp "$NAME:/opt/b4-1/logs" "$HERE/logs"
mkdir -p "$HERE/docs"
docker cp "$NAME:/opt/b4-1/docs/report.md" "$HERE/docs/report.md"

echo
echo "완료. 체크리스트: logs/00-checklist.log"
echo "  서버 셸     : ./setup.sh shell"
echo "  SSH 접속    : ./setup.sh ssh   (호스트 포트 $HOST_SSH_PORT)"
echo "  앱 포트     : 127.0.0.1:$HOST_APP_PORT"
