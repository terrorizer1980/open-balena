FROM haproxy:1.9-alpine

VOLUME [ "/certs" ]

RUN apk add --update bash inotify-tools

COPY haproxy.cfg /usr/local/etc/haproxy/haproxy.cfg
COPY start-haproxy.sh /start-haproxy

COPY ./entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT [ "/entrypoint.sh" ]
CMD [ "/start-haproxy" ]
