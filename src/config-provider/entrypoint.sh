#!/bin/sh

if [ -z "$CONFD_BACKEND" ]; then
    echo "Locking updates..."
    flock /tmp/balena/updates.lock -c "$@"
fi

rm -f /tmp/balena/updates.lock || true 
echo "Idling..."
while true; do
    sleep 1;
done
