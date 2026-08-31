#!/usr/bin/env bash
# Installs the k3s image-prune service + timer on the k3s node (CT 200 on the
# PVE host). Node-level things cannot be GitOps (same as
# install-smartctl-exporter.sh): the CronJob-shaped alternative would need
# hostPath mounts and privileges that widen the attack surface for no gain,
# so this is a systemd timer on the node instead.
#
# Run from a checkout of this repo: ./scripts/install-image-prune.sh
#
# See docs/doctor-log.md (2026-08-31, disk-pressure churn loop) and
# issue #11 for why this exists: the node sits at the kubelet's 15% imagefs
# eviction threshold, and crossing it evicts authentik (SSO for everything),
# argocd-repo-server (no app can sync) and the media stack.
set -euo pipefail

PVE_HOST=${PVE_HOST:-root@100.125.108.56}
SSH_KEY=${SSH_KEY:-"$HOME/.ssh/worker_key"}
CT=200

PRUNE_SCRIPT='#!/bin/sh
# k3s-image-prune: reclaim containerd/journal space on the k3s node.
# Guards, each learned the hard way (docs/doctor-log.md, issue #11):
# 1. NEVER prune while any pod is Pending - the prune deletes images those
#    pods are about to use, and the next scheduling retry re-pulls them,
#    re-filling the disk (the prune-then-repull trap).
# 2. Only prune below the floor; pruning churns the content store and
#    briefly increases IO on an already struggling disk.
# 3. Exited containers pin images - remove them first or the prune frees
#    nothing (observed: prune "freed" 3 images while 41G sat in content).
set -eu
FLOOR_GB=15
free=$(df -BG --output=avail / | tail -1 | tr -dc "0-9")
if [ "$free" -ge "$FLOOR_GB" ]; then
  echo "free ${free}G >= floor ${FLOOR_GB}G - nothing to do"
  exit 0
fi
pending=$(/usr/local/bin/k3s kubectl get pods -A --field-selector=status.phase=Pending --no-headers 2>/dev/null | wc -l)
if [ "$pending" -gt 0 ]; then
  echo "${pending} pod(s) Pending - skipping prune (prune-then-repull trap)"
  exit 0
fi
echo "free ${free}G below floor ${FLOOR_GB}G - pruning"
/usr/local/bin/k3s kubectl delete pods -A --field-selector=status.phase=Failed --wait=false --ignore-not-found >/dev/null 2>&1 || true
for c in $(/usr/local/bin/k3s crictl ps -aq --state Exited 2>/dev/null); do
  /usr/local/bin/k3s crictl rm "$c" >/dev/null 2>&1 || true
done
/usr/local/bin/k3s crictl rmi --prune 2>&1 | tail -1 || true
journalctl --vacuum-size=100M >/dev/null 2>&1 || true
fstrim -v / >/dev/null 2>&1 || true
echo "prune done; free now: $(df -BG --output=avail / | tail -1)"
'

SERVICE_UNIT='[Unit]
Description=Reclaim containerd/journal space on the k3s node when below the floor
# Persistent node: the timer state survives reboots, unlike the transient
# boot-test timer that died with its reboot (docs/doctor-log.md).
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/k3s-image-prune
'

TIMER_UNIT='[Unit]
Description=Run k3s-image-prune every 6 hours

[Timer]
OnCalendar=*-*-* 00/6:00:00
RandomizedDelaySec=10m
Persistent=true

[Install]
WantedBy=timers.target
'

echo "installing k3s-image-prune on CT ${CT} via ${PVE_HOST}"
ssh -i "$SSH_KEY" -o IdentitiesOnly=yes -o BatchMode=yes "$PVE_HOST" "pct exec $CT -- bash -s" <<REMOTE
set -eu
cat > /usr/local/sbin/k3s-image-prune <<'PRUNE'
${PRUNE_SCRIPT}
PRUNE
chmod 755 /usr/local/sbin/k3s-image-prune
cat > /etc/systemd/system/k3s-image-prune.service <<'SVC'
${SERVICE_UNIT}
SVC
cat > /etc/systemd/system/k3s-image-prune.timer <<'TMR'
${TIMER_UNIT}
TMR
systemctl daemon-reload
systemctl enable --now k3s-image-prune.timer
echo "--- timer ---"
systemctl list-timers k3s-image-prune.timer --no-pager | head -3
echo "--- first run ---"
systemctl start k3s-image-prune.service
journalctl -u k3s-image-prune.service --no-pager | tail -4
REMOTE
