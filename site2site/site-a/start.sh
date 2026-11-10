#!/bin/sh
set -e

echo "Configuring Site A firewall..."

# Install networking tools
apk add --no-cache iproute2 wireguard-tools

# Configure Site A security zones
ip addr replace 192.0.2.1/26 dev eth1
ip addr replace 192.0.2.65/26 dev eth2
ip addr replace 192.0.2.129/26 dev eth3

# Configure private underlay
ip addr replace 203.0.113.1/29 dev eth4

# Bring interfaces up
ip link set eth1 up
ip link set eth2 up
ip link set eth3 up
ip link set eth4 up

# Create WireGuard interface
ip link show wg0 >/dev/null 2>&1 || ip link add wg0 type wireguard

# Configure WireGuard tunnel address
ip addr replace 10.255.0.1/30 dev wg0
ip link set wg0 up

# Configure WireGuard peer
wg set wg0 \
    private-key /run/wireguard/privatekey \
    listen-port 51820 \
    peer xzA1+SeNrEbZFQwOoSCTkJ4siHRZITvsVVmL2bwHlgE= \
    endpoint 203.0.113.2:51820 \
    allowed-ips 10.255.0.2/32,198.51.100.10/32 \
    persistent-keepalive 25

# Route Site B collector traffic through WireGuard
ip route replace 198.51.100.10/32 dev wg0

echo "Site A firewall configuration complete."
