#!/bin/sh
set -e

echo "Configuring Site B firewall..."

# Install networking tools
sysctl -w net.ipv4.ip_forward=1
apk add --no-cache iproute2 wireguard-tools

# Configure private underlay
ip addr replace 203.0.113.2/29 dev eth1

# Configure collector network
ip addr replace 198.51.100.1/24 dev eth2

# Bring interfaces up
ip link set eth1 up
ip link set eth2 up

# Create WireGuard interface
ip link show wg0 >/dev/null 2>&1 || ip link add wg0 type wireguard

# Configure WireGuard tunnel address
ip addr replace 10.255.0.2/30 dev wg0
ip link set wg0 up

# Configure WireGuard peer
wg set wg0 \
    private-key /run/wireguard/privatekey \
    listen-port 51820 \
    peer WToBmOeJUXYbeqM/JvC3eOx19RlgYAEes/BqAGjklGk= \
    endpoint 203.0.113.1:51820 \
    allowed-ips 10.255.0.1/32 \
    persistent-keepalive 25

echo "Site B firewall configuration complete."
