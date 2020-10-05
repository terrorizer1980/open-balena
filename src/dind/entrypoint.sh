#!/bin/bash
set -e

# write our CA cert to file and load it into the system
echo "$_BALENA_ROOT_CA" | base64 -d > /usr/local/share/ca-certificates/balena.crt
export NODE_EXTRA_CA_CERTS="/usr/local/share/ca-certificates/balena.crt"
update-ca-certificates

# add our cert to the DIND container to trust the registry
mkdir -p "/etc/docker/certs.d/vpn.$DOMAIN:443/"
cp "/usr/local/share/ca-certificates/balena.crt" "/etc/docker/certs.d/vpn.$DOMAIN:443/ca.crt"

# link the DBUS & docker sockets
ln -s /host/run/dbus /var/run/dbus

avahi-daemon -D

echo "==> Launching the Docker daemon..."
CMD=$*
if [ "$CMD" == '' ];then
  dind dockerd $DOCKER_EXTRA_OPTS
  check_docker
else
  dind dockerd $DOCKER_EXTRA_OPTS &
  while(! docker info > /dev/null 2>&1); do
      echo "==> Waiting for the Docker daemon to come online..."
      sleep 1
  done
  echo "==> Docker Daemon is up and running!"
  echo "==> Running CMD $CMD!"
  exec "$CMD"
fi