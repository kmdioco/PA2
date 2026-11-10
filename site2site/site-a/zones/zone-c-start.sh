#!/bin/sh
set -e
apk add --no-cache iproute2
ip addr replace 192.0.2.130/26 dev eth1
ip link set eth1 up
ip route replace 192.0.2.0/26 via 192.0.2.129
ip route replace 192.0.2.64/26 via 192.0.2.129
echo "Zone C host configured."
