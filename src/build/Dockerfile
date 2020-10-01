ARG BASE_IMAGE
FROM $BASE_IMAGE

COPY ./entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT [ "/entrypoint.sh" ]
CMD [ "/usr/bin/entry.sh" ]