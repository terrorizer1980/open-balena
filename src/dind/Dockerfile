FROM domofactor/dind-jessie

RUN apt update && apt install -y \
    libnss-mdns \
    avahi-daemon \
    avahi-utils

COPY ./etc/avahi-daemon.conf /etc/avahi/avahi-daemon.conf
COPY ./etc/mdns.allow /etc/mdns.allow

RUN sed -i 's/mdns4_minimal/mdns4/g' /etc/nsswitch.conf

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
