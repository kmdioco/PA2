#!/bin/sh
set -e

echo "Configuring Site B log collector..."

# Install networking tools
apk add --no-cache iproute2

# Configure collector network
ip addr replace 198.51.100.10/24 dev eth1
ip link set eth1 up

# Route return traffic to Site A through Site B firewall
ip route replace 10.255.0.1/32 via 198.51.100.1

echo "Site B log collector configuration complete."
