#!/usr/bin/env bash
# Install smartctl_exporter as a systemd service on a bare-metal host.
#
# This is the one piece of monitoring that cannot be a DaemonSet. The disks
# belong to the Proxmox host and to the NAS, not to the k3s container: LXC 200
# has no block devices in /dev at all, so a pod has nothing to read. Passing the
# NVMe through would still cover only the Proxmox boot disk and would miss the
# NAS entirely - which is where the 21TB of pool disks actually live.
#
# So the exporter runs on the hosts and Prometheus scrapes it over the LAN. The
# scrape config, alert rules and dashboard stay in GitOps; only this binary does
# not, because ArgoCD has no reach outside the cluster.
#
# Usage: run as root on the target host, or pipe it in:
#   ssh HOST 'bash -s' < scripts/install-smartctl-exporter.sh
set -euo pipefail

VERSION="0.14.0"
PORT="9633"
ARCH="linux-amd64"
TARBALL="smartctl_exporter-${VERSION}.${ARCH}.tar.gz"
URL="https://github.com/prometheus-community/smartctl_exporter/releases/download/v${VERSION}/${TARBALL}"

# doas on the NAS, nothing when already root. sudo is deliberately not used -
# it demands a password there.
if [ "$(id -u)" -eq 0 ]; then AS_ROOT=""; else AS_ROOT="doas"; fi

command -v smartctl >/dev/null || { echo "smartctl not installed; install smartmontools first" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL --retry 3 -o "$tmp/$TARBALL" "$URL"
tar -xzf "$tmp/$TARBALL" -C "$tmp"
$AS_ROOT install -m 0755 "$tmp/smartctl_exporter-${VERSION}.${ARCH}/smartctl_exporter" /usr/local/bin/smartctl_exporter

# Runs as root on purpose. SMART data comes from SG_IO / NVMe admin passthrough
# ioctls on the raw device, which an unprivileged user cannot issue. The unit is
# locked down everywhere else instead: read-only filesystem, no new privileges,
# and the LAN-only listener.
$AS_ROOT tee /etc/systemd/system/smartctl_exporter.service >/dev/null <<UNIT
[Unit]
Description=smartctl_exporter (Prometheus SMART metrics)
Documentation=https://github.com/prometheus-community/smartctl_exporter
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/smartctl_exporter --web.listen-address=:${PORT} --smartctl.path=$(command -v smartctl)
Restart=on-failure
RestartSec=10
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
UNIT

$AS_ROOT systemctl daemon-reload
$AS_ROOT systemctl enable --now smartctl_exporter.service
sleep 3
$AS_ROOT systemctl is-active smartctl_exporter.service
curl -fsS "http://127.0.0.1:${PORT}/metrics" | grep -c '^smartctl_device' | xargs printf 'smartctl_device metrics exposed: %s\n'
