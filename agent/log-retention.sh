#!/bin/bash
# log-retention.sh - 시간 기반 로그 보존 정책(보너스 2)
#
#   1) /var/log/agent-app/*.log 중 7일 이상 지난 파일을 gzip 으로 압축해
#   2) /var/log/monitor/agent-app/archive/ 로 옮기고
#   3) archive/*.gz 중 30일 이상 지난 파일을 지운다.
#
# 디렉터리가 없거나 권한이 없거나 대상이 0개여도 실패로 끝내지 않고 경고만 남긴다.
# cron 에서 매일 돌리는 작업이라, 하루 실패로 다음 날 작업까지 멈추면 안 되기 때문이다.

PATH=/usr/local/bin:/usr/bin:/bin
SRC_DIR=${LOG_SRC:-/var/log/agent-app}
ARCHIVE_DIR=${LOG_ARCHIVE:-/var/log/monitor/agent-app/archive}
COMPRESS_DAYS=${COMPRESS_DAYS:-7}
DELETE_DAYS=${DELETE_DAYS:-30}

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

if [ ! -d "$SRC_DIR" ]; then
    log "[WARNING] 원본 로그 디렉터리가 없다: $SRC_DIR (건너뜀)"
    exit 0
fi
if ! mkdir -p "$ARCHIVE_DIR" 2>/dev/null || [ ! -w "$ARCHIVE_DIR" ]; then
    log "[WARNING] 아카이브 디렉터리를 만들거나 쓸 권한이 없다: $ARCHIVE_DIR (건너뜀)"
    exit 0
fi
if [ ! -w "$SRC_DIR" ]; then
    log "[WARNING] 원본 로그 디렉터리에 쓰기 권한이 없어 이동할 수 없다: $SRC_DIR (건너뜀)"
    exit 0
fi

# find -mtime +N 은 "N*24시간을 넘긴" 파일이다. 7일 이상 경과 = +6.
compressed=0
while IFS= read -r -d '' file; do
    stamp=$(date -r "$file" +%Y%m%d)
    target="$ARCHIVE_DIR/$(basename "$file").$stamp.gz"
    if gzip -c "$file" > "$target" 2>/dev/null; then
        touch -r "$file" "$target"          # 보관 기간 계산이 원본 시각을 따르도록
        rm -f "$file"
        log "[ARCHIVE] $file -> $target"
        compressed=$(( compressed + 1 ))
    else
        rm -f "$target"
        log "[WARNING] 압축 실패(권한 확인 필요): $file"
    fi
done < <(find "$SRC_DIR" -maxdepth 1 -type f -name '*.log' -mtime +$(( COMPRESS_DAYS - 1 )) -print0 2>/dev/null)
[ "$compressed" -eq 0 ] && log "[INFO] ${COMPRESS_DAYS}일 이상 지난 로그가 없다."

deleted=0
while IFS= read -r -d '' gz; do
    if rm -f "$gz" 2>/dev/null; then
        log "[DELETE] $gz"
        deleted=$(( deleted + 1 ))
    else
        log "[WARNING] 삭제 실패(권한 확인 필요): $gz"
    fi
done < <(find "$ARCHIVE_DIR" -maxdepth 1 -type f -name '*.gz' -mtime +$(( DELETE_DAYS - 1 )) -print0 2>/dev/null)
[ "$deleted" -eq 0 ] && log "[INFO] ${DELETE_DAYS}일 이상 지난 아카이브가 없다."

log "[DONE] 압축 ${compressed}건, 삭제 ${deleted}건"
exit 0
