#!/bin/sh
# Prepare a postmarketOS phone to run as a k3s agent. Run ON the phone as root.
#
# Does everything except joining and the USB subnet change, both of which are
# separate on purpose: joining needs the home network, and the subnet change
# needs a reboot that would drop the connection you are running this over.
#
# Idempotent - safe to re-run.
#
# See docs/phone-nodes.md for the host side and the three non-obvious traps.
set -eu

K3S_VERSION="${K3S_VERSION:-v1.31.5+k3s1}"   # MUST match the server
say() { printf '  %s\n' "$*"; }

[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }

echo "== 1. packages =="
apk add --quiet chrony iptables ip6tables 2>&1 | tail -1 || true
say "chrony, iptables installed"

echo "== 2. time =="
# These phones have no working RTC and boot at 1970. A wrong clock breaks TLS
# to the API server and reports itself as a *certificate* error, which sends
# you looking in entirely the wrong place. chronyd depends on OpenRC's
# `networking`, which never starts here (nothing populates
# /etc/network/interfaces; the USB link is brought up by the initramfs), so it
# has to be started with --nodeps.
rc-update add chronyd default >/dev/null 2>&1 || true
rc-service --nodeps chronyd restart >/dev/null 2>&1 || true
say "chrony enabled at boot (start with --nodeps; see note above)"

echo "== 3. cgroup v2 =="
# This kernel has CONFIG_MEMCG=y but CONFIG_MEMCG_V1 unset, so the `memory`
# controller exists ONLY in the unified hierarchy. Without this, /proc/cgroups
# shows no `memory` and kubelet refuses to start - which looks like an
# unsupported kernel but is only a mode setting.
if grep -q '^#rc_cgroup_mode=' /etc/rc.conf 2>/dev/null; then
  sed -i 's/^#rc_cgroup_mode=.*/rc_cgroup_mode="unified"/' /etc/rc.conf
fi
grep -q '^rc_cgroup_mode="unified"' /etc/rc.conf 2>/dev/null \
  || echo 'rc_cgroup_mode="unified"' >> /etc/rc.conf
rc-update add cgroups boot >/dev/null 2>&1 || true
rc-service cgroups start >/dev/null 2>&1 || true
say "cgroup mode: $(grep '^rc_cgroup_mode' /etc/rc.conf)"

echo "== 4. kernel modules =="
for m in overlay br_netfilter nf_conntrack ip_tables vxlan; do
  grep -qx "$m" /etc/modules 2>/dev/null || echo "$m" >> /etc/modules
  modprobe "$m" 2>/dev/null || true
done
say "modules loaded and persisted in /etc/modules"

echo "== 5. sysctl =="
printf 'net.bridge.bridge-nf-call-iptables=1\nnet.bridge.bridge-nf-call-ip6tables=1\nnet.ipv4.ip_forward=1\n' \
  > /etc/sysctl.d/99-k3s.conf
sysctl -p /etc/sysctl.d/99-k3s.conf >/dev/null 2>&1 || true
say "bridge-nf + ip_forward set"

echo "== 6. k3s binary =="
NEED=1
if [ -x /usr/local/bin/k3s ]; then
  HAVE=$(/usr/local/bin/k3s --version 2>/dev/null | head -1 | awk '{print $3}')
  [ "$HAVE" = "$K3S_VERSION" ] && NEED=0 && say "k3s $HAVE already present"
fi
if [ "$NEED" = 1 ]; then
  ENC=$(echo "$K3S_VERSION" | sed 's/+/%2B/')
  wget -q -O /usr/local/bin/k3s \
    "https://github.com/k3s-io/k3s/releases/download/${ENC}/k3s-arm64"
  chmod +x /usr/local/bin/k3s
  say "installed $(/usr/local/bin/k3s --version 2>/dev/null | head -1 | awk '{print $3}')"
fi

echo "== 7. verify =="
grep -qw memory /sys/fs/cgroup/cgroup.controllers 2>/dev/null \
  && say "memory controller: OK" \
  || say "memory controller: MISSING (reboot may be required)"
grep -qw overlay /proc/filesystems && say "overlayfs: OK" || say "overlayfs: MISSING"
# strip ANSI colour before matching - k3s colourises STATUS and a plain
# ^STATUS grep silently reports "unknown" on a perfectly good check.
STATUS=$(/usr/local/bin/k3s check-config 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E '^STATUS' | tail -1)
say "k3s check-config -> ${STATUS:-unknown}"

echo
say "staged. next: stage the node token, then run join-cluster.sh on the home network."
