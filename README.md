## IMPORTANT:
The topology assumes the Codespace username is codespace, because the private-key mounts use /home/codespace. Please adjust as needed.

The WireGuard placeholders <SITE_A_PUBLIC_KEY> & <SITE_B_PUBLIC_KEY> must be replaced in the actual startup files before deployment. Do not leave the placeholders in the working configuration.

Keep private keys out of Git. Only the public keys are used in the startup scripts.

The collector log directory is mounted from the repository workspace, so collected logs persist across container destruction and redeployment as long as the Codespace workspace remains.

If issues arise, please refer to the PracticalAssessment_Dioco file and follow the documentation there.

## Project Structure

```text
site2site/
├── topology.clab.yml
├── site-a/
│   ├── start.sh
│   ├── nftables.conf
│   ├── ulogd.conf
│   ├── rsyslog.d/
│   │   └── 10-site-a-forward.conf
│   └── zones/
│       ├── zone-a-start.sh
│       ├── zone-b-start.sh
│       └── zone-c-start.sh
└── site-b/
    ├── start.sh
    ├── nftables.conf
    └── collector/
        ├── start.sh
        ├── rsyslog.d/
        │   └── 10-site-a-remote.conf
        └── logs/
```

# Documentation

*Run the commands from the repository root in GitHub Codespaces.*

## Initial setup

### added .gitignore

`.gitignore`

```gitignore
# WireGuard private keys
**/privatekey

# Environment files and secrets
.env
.env.*
!.env.example

# Runtime logs
site2site/site-b/collector/logs/*.log

# Temporary files
*.tmp
*.swp
*~

# Operating system files
.DS_Store
Thumbs.db

# Containerlab generated files
site2site/clab-*/
```

### installed containerlab

```bash
bash -c "$(curl -sL https://get.containerlab.dev)"
```

### added admin status in containerlab

```bash
sudo usermod -aG clab_admins "$USER" && newgrp clab_admins
```

### created and stored wireguard keys securely

```bash
mkdir -p -m 700 "$HOME/.config/pa2/site-a"
mkdir -p -m 700 "$HOME/.config/pa2/site-b"

docker run --rm alpine:latest sh -c \
  'apk add --no-cache wireguard-tools >/dev/null && wg genkey' \
  > "$HOME/.config/pa2/site-a/privatekey"

docker run --rm alpine:latest sh -c \
  'apk add --no-cache wireguard-tools >/dev/null && wg genkey' \
  > "$HOME/.config/pa2/site-b/privatekey"

chmod 600 "$HOME/.config/pa2/site-a/privatekey"
chmod 600 "$HOME/.config/pa2/site-b/privatekey"
```

### generated public keys

```bash
echo "Site A public key:"
docker run --rm -i alpine:latest sh -c \
  'apk add --no-cache wireguard-tools >/dev/null && wg pubkey' \
  < "$HOME/.config/pa2/site-a/privatekey"

echo "Site B public key:"
docker run --rm -i alpine:latest sh -c \
  'apk add --no-cache wireguard-tools >/dev/null && wg pubkey' \
  < "$HOME/.config/pa2/site-b/privatekey"
```

The Site A startup script must contain the Site B public key as its peer. The Site B startup script must contain the Site A public key as its peer.

Replace the corresponding peer public key values in:

- `site2site/site-a/start.sh`
- `site2site/site-b/start.sh`

Generate new keys only when setting up a fresh Codespace. Keep the existing keys when destroying and redeploying the lab.

## Configuration files

### configured Site A firewall startup

`site2site/site-a/start.sh`

```sh
#!/bin/sh
set -e

echo "Configuring Site A firewall..."

# Install networking tools
sysctl -w net.ipv4.ip_forward=1
apk add --no-cache iproute2 wireguard-tools nftables ulogd rsyslog

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
    peer <SITE_B_PUBLIC_KEY> \
    endpoint 203.0.113.2:51820 \
    allowed-ips 10.255.0.2/32,198.51.100.10/32 \
    persistent-keepalive 25

# Route Site B collector traffic through WireGuard
ip route replace 198.51.100.10/32 dev wg0

# Load persistent firewall policy
nft -f /etc/nftables.conf

# Start NFLOG listener for firewall traffic events
ulogd -c /etc/ulogd-pa2.conf -d

# Validate and start firewall log forwarding
rsyslogd -N1 -f /etc/rsyslog.conf
rsyslogd

echo "Site A firewall configuration complete."
```

### configured Zone A host

`site2site/site-a/zones/zone-a-start.sh`

```sh
#!/bin/sh
set -e
apk add --no-cache iproute2
ip addr replace 192.0.2.2/26 dev eth1
ip link set eth1 up
ip route replace 192.0.2.64/26 via 192.0.2.1
ip route replace 192.0.2.128/26 via 192.0.2.1
echo "Zone A host configured."
```

### configured Zone B host

`site2site/site-a/zones/zone-b-start.sh`

```sh
#!/bin/sh
set -e
apk add --no-cache iproute2
ip addr replace 192.0.2.66/26 dev eth1
ip link set eth1 up
ip route replace 192.0.2.0/26 via 192.0.2.65
ip route replace 192.0.2.128/26 via 192.0.2.65
echo "Zone B host configured."
```

### configured Zone C host

`site2site/site-a/zones/zone-c-start.sh`

```sh
#!/bin/sh
set -e
apk add --no-cache iproute2
ip addr replace 192.0.2.130/26 dev eth1
ip link set eth1 up
ip route replace 192.0.2.0/26 via 192.0.2.129
ip route replace 192.0.2.64/26 via 192.0.2.129
echo "Zone C host configured."
```

### configured Site A firewall rules

`site2site/site-a/nftables.conf`

```nft
#!/usr/sbin/nft -f

flush ruleset

table inet filter {
    chain input {
        type filter hook input priority filter; policy drop;

        iifname "lo" accept
        ct state established,related accept

        # Preserve Containerlab management access
        iifname "eth0" accept

        # Allow WireGuard from Site B
        iifname "eth4" udp dport 51820 accept

        # Allow zone hosts to reach their own gateway
        iifname "eth1" ip saddr 192.0.2.0/26 icmp type echo-request limit rate 5/second log group 5 prefix "SITEA-INPUT-ALLOW "
        iifname "eth1" ip saddr 192.0.2.0/26 icmp type echo-request accept
        iifname "eth2" ip saddr 192.0.2.64/26 icmp type echo-request limit rate 5/second log group 5 prefix "SITEA-INPUT-ALLOW "
        iifname "eth2" ip saddr 192.0.2.64/26 icmp type echo-request accept
        iifname "eth3" ip saddr 192.0.2.128/26 icmp type echo-request limit rate 5/second log group 5 prefix "SITEA-INPUT-ALLOW "
        iifname "eth3" ip saddr 192.0.2.128/26 icmp type echo-request accept

        # Log and drop other inbound traffic
        limit rate 5/second log group 5 prefix "SITEA-INPUT-DROP "
        drop
    }

    chain forward {
        type filter hook forward priority filter; policy drop;

        # Log and drop inter-zone and other forwarded traffic
        counter limit rate 5/second log group 5 prefix "SITEA-FORWARD-DROP "
        drop
    }

    chain output {
        type filter hook output priority filter; policy accept;
    }
}
```

### configured Site A ulogd

`site2site/site-a/ulogd.conf`

```ini
[global]
logfile="/var/log/ulogd.log"
loglevel=5

plugin="/usr/lib/ulogd/ulogd_inppkt_NFLOG.so"
plugin="/usr/lib/ulogd/ulogd_raw2packet_BASE.so"
plugin="/usr/lib/ulogd/ulogd_filter_IFINDEX.so"
plugin="/usr/lib/ulogd/ulogd_filter_IP2STR.so"
plugin="/usr/lib/ulogd/ulogd_filter_PRINTPKT.so"
plugin="/usr/lib/ulogd/ulogd_output_LOGEMU.so"

stack=log5:NFLOG,base1:BASE,ifi1:IFINDEX,ip2str1:IP2STR,print1:PRINTPKT,emu1:LOGEMU

[log5]
group=5
bind=1

[emu1]
file="/var/log/site-a-firewall.log"
sync=1
```

### configured Site A rsyslog forwarding

`site2site/site-a/rsyslog.d/10-site-a-forward.conf`

```rsyslog
module(load="imfile")

input(
    type="imfile"
    File="/var/log/site-a-firewall.log"
    Tag="site-a-firewall:"
    Severity="info"
    Facility="local0"
    PersistStateInterval="100"
)

action(
    type="omfwd"
    Target="198.51.100.10"
    Port="514"
    Protocol="tcp"
    action.resumeRetryCount="-1"
    queue.type="linkedList"
    queue.filename="siteAForward"
)
```

### configured Site B firewall startup

`site2site/site-b/start.sh`

```sh
#!/bin/sh
set -e

echo "Configuring Site B firewall..."

# Install networking tools
sysctl -w net.ipv4.ip_forward=1
apk add --no-cache iproute2 wireguard-tools nftables

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
    peer <SITE_A_PUBLIC_KEY> \
    endpoint 203.0.113.1:51820 \
    allowed-ips 10.255.0.1/32 \
    persistent-keepalive 25

# Load persistent Site B firewall policy
nft -c -f /etc/nftables.conf
nft -f /etc/nftables.conf

echo "Site B firewall configuration complete."
```

### configured Site B firewall rules

`site2site/site-b/nftables.conf`

```nft
#!/usr/sbin/nft -f

flush ruleset

table inet filter {
    chain input {
        type filter hook input priority filter; policy drop;

        # Allow loopback
        iifname "lo" accept

        # Allow established connections
        ct state established,related accept

        # Preserve Containerlab management access
        iifname "eth0" accept

        # Allow WireGuard from Site A
        iifname "eth1" udp dport 51820 accept

        # Allow tunnel connectivity testing
        iifname "wg0" ip saddr 10.255.0.1 icmp type echo-request accept

        counter drop
    }

    chain forward {
        type filter hook forward priority filter; policy drop;

        # Allow established return traffic
        ct state established,related accept

        # Allow Site A firewall logs to reach the collector
        iifname "wg0" oifname "eth2" \
            ip saddr 10.255.0.1 \
            ip daddr 198.51.100.10 \
            tcp dport 514 accept

        counter drop
    }

    chain output {
        type filter hook output priority filter; policy accept;
    }
}
```

### configured Site B collector startup

`site2site/site-b/collector/start.sh`

```sh
#!/bin/sh
set -e

echo "Configuring Site B log collector..."

# Install networking tools and rsyslog
apk add --no-cache iproute2 rsyslog

# Configure collector network
ip addr replace 198.51.100.10/24 dev eth1
ip link set eth1 up

# Route return traffic to Site A through Site B firewall
ip route replace 10.255.0.1/32 via 198.51.100.1

# Start rsyslog in the background
rsyslogd

echo "Site B log collector configuration complete."
```

### configured Site B rsyslog receiver

`site2site/site-b/collector/rsyslog.d/10-site-a-remote.conf`

```rsyslog
module(load="imtcp")

input(
    type="imtcp"
    address="198.51.100.10"
    port="514"
)

if ($fromhost-ip == "10.255.0.1") then {
    action(type="omfile" file="/var/log/collected/site-a.log")
    stop
}
```

## Topology

### configured Containerlab topology

`site2site/topology.clab.yml`

```yaml
name: pa2

topology:
  nodes:
    site-a-fw:
      kind: linux
      image: alpine:latest
      binds:
        - site-a/start.sh:/start.sh:ro
        - site-a/nftables.conf:/etc/nftables.conf:ro
        - site-a/ulogd.conf:/etc/ulogd-pa2.conf:ro
        - site-a/rsyslog.d:/etc/rsyslog.d:ro
        - /home/codespace/.config/pa2/site-a/privatekey:/run/wireguard/privatekey:ro
      exec:
        - sh /start.sh

    zone-a-host:
      kind: linux
      image: alpine:latest
      binds:
        - site-a/zones/zone-a-start.sh:/start.sh:ro
      exec:
        - sh /start.sh

    zone-b-host:
      kind: linux
      image: alpine:latest
      binds:
        - site-a/zones/zone-b-start.sh:/start.sh:ro
      exec:
        - sh /start.sh

    zone-c-host:
      kind: linux
      image: alpine:latest
      binds:
        - site-a/zones/zone-c-start.sh:/start.sh:ro
      exec:
        - sh /start.sh

    site-b-fw:
      kind: linux
      image: alpine:latest
      binds:
        - site-b/start.sh:/start.sh:ro
        - site-b/nftables.conf:/etc/nftables.conf:ro
        - /home/codespace/.config/pa2/site-b/privatekey:/run/wireguard/privatekey:ro
      exec:
        - sh /start.sh

    site-b-collector:
      kind: linux
      image: alpine:latest
      binds:
        - site-b/collector/start.sh:/start.sh:ro
        - site-b/collector/rsyslog.d:/etc/rsyslog.d:ro
        - site-b/collector/logs:/var/log/collected
      exec:
        - sh /start.sh

  links:
    # Site A security zones
    - endpoints: ["site-a-fw:eth1", "zone-a-host:eth1"]
    - endpoints: ["site-a-fw:eth2", "zone-b-host:eth1"]
    - endpoints: ["site-a-fw:eth3", "zone-c-host:eth1"]

    # Simulated private underlay between sites
    - endpoints: ["site-a-fw:eth4", "site-b-fw:eth1"]

    # Site B collector network
    - endpoints: ["site-b-fw:eth2", "site-b-collector:eth1"]
```

## Deployment

### prepared collector log directory

```bash
mkdir -p site2site/site-b/collector/logs
```

### deployed topology and startup configurations

```bash
containerlab deploy -t site2site/topology.clab.yml
```

The topology automatically creates the six containers, connects the network interfaces, mounts the configuration files, and executes the startup scripts.

The startup scripts automatically configure:

- Site A firewall interfaces and three security zones
- Site B firewall and collector network
- WireGuard interfaces, peers, and routes
- nftables firewall policies
- ulogd NFLOG collection
- rsyslog forwarding and collection

### destroyed the lab

```bash
containerlab destroy -t site2site/topology.clab.yml
```