#!/bin/sh
set -e
apk add --no-cache iproute2
ip addr replace 192.0.2.2/26 dev eth1
ip link set eth1 up
ip route replace 192.0.2.64/26 via 192.0.2.1
ip route replace 192.0.2.128/26 via 192.0.2.1
echo "Zone A host configured."
