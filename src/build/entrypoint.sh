#!/bin/bash

while read -r line; do
  export "${line?}"
done < <(env | grep ^_BALENA | cut -c 2-)


exec "$@"