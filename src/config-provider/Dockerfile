FROM alpine

RUN apk add --no-cache bash coreutils curl easy-rsa openssl jq ncurses util-linux
RUN mkdir -p /tmp/balena

WORKDIR /
COPY quickstart.sh /quickstart.sh
COPY entrypoint.sh /entrypoint.sh
COPY scripts scripts

ENTRYPOINT [ "/entrypoint.sh" ]
CMD [ "/quickstart.sh" ]
