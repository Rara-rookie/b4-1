# b4-1 실습 서버: Ubuntu 22.04 LTS
# 과제가 요구하는 서비스(sshd, ufw, acl, cron)와 점검 도구(ss, ps, pgrep)만 설치한다.
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Seoul \
    LANG=C.UTF-8

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      openssh-server openssh-client ufw acl cron sudo procps iproute2 \
      unzip tzdata ca-certificates less vim-tiny \
 && rm -rf /var/lib/apt/lists/* \
 # TZ 환경변수는 su - 로 바뀐 로그인 셸에 전달되지 않는다. 시스템 시각대를 고정해 앱·cron·monitor 로그 시각을 맞춘다.
 && ln -snf /usr/share/zoneinfo/Asia/Seoul /etc/localtime && echo Asia/Seoul > /etc/timezone \
 # 컨테이너에는 로그인 세션이 없어 pam_loginuid 가 실패하고 cron 이 사용자 작업을 건너뛴다.
 && sed -i 's/^session\s\+required\s\+pam_loginuid.so/#&/' /etc/pam.d/cron \
 && mkdir -p /run/sshd

WORKDIR /opt/b4-1
