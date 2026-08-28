# Pixel 3a phones as k3s nodes

Three Pixel 3a handsets running **postmarketOS v26.06** (aarch64, kernel
`7.0.10-sdm670`), intended as k3s agent nodes. Each has 8 cores, 3.5 GB RAM and
~45 GB free — comparable to a small cloud worker.

**Two of the three have dead WiFi**, so they attach over **USB ethernet to the
Proxmox host** rather than the LAN.

| Phone | WiFi | Path |
|---|---|---|
| `pixel3a1` | broken | USB only |
| `pixel3a2` | broken | USB only |
| `pixel3a3` | works (`192.168.1.175`) | WiFi, or USB |

Credentials live in Doppler, project `kubernetes`, config **`dev`**
(`PIXEL3A{1,2,3}_PASS`). SSH is key-based as user `travis` with `worker_key`;
`root` login is refused.

## Three things that will bite you

### 1. The clock starts at 1970

These phones have no working RTC. They boot at `Jan 1970`, which breaks TLS to
the API server — and it surfaces as a **certificate verification error**, not a
clock error, so it sends you looking in the wrong place.

`chrony` is installed and enabled at boot. Note it depends on OpenRC's
`networking` service, which does **not** start here (nothing populates
`/etc/network/interfaces`; the USB link is brought up by the initramfs). Start
it with `rc-service --nodeps chronyd start`, or give `networking` something to
do. `join-cluster.sh` checks the clock first and tries to fix it.

### 2. `memory` cgroup exists only under cgroup v2

`/proc/cgroups` does not list `memory`, which looks fatal for kubelet. It isn't:

```
CONFIG_MEMCG=y                 # compiled in
# CONFIG_MEMCG_V1 is not set   # but v1 only
```

The controller exists solely in the **unified hierarchy**. Fixed by setting
`rc_cgroup_mode="unified"` in `/etc/rc.conf` and adding `cgroups` to the `boot`
runlevel. After that:

```
$ cat /sys/fs/cgroup/cgroup.controllers
cpuset cpu io memory hugetlb pids
```

Everything else containerd/flannel needs is present as modules
(`overlay`, `br_netfilter`, `nf_conntrack`, `ip_tables`, `vxlan`) and is listed
in `/etc/modules`. `k3s check-config` reports **`STATUS: pass`**.

### 3. Every phone claims 172.16.42.1 — they collide

postmarketOS ships the same USB address on every device, so plugging two into
one machine gives you two interfaces fighting over one subnet (observed: the
second phone got no IPv4 at all). Each phone needs its own range.

The addresses come from `/etc/unudhcpd.conf`:

```
unudhcpd_host_ip=172.16.42.1     # the phone itself
unudhcpd_client_ip=172.16.42.2   # the machine you plug into
```

**The file is read by the initramfs, not at runtime** — editing it does nothing
until you rebuild:

```sh
sudo sed -i 's/^unudhcpd_host_ip=.*/unudhcpd_host_ip=172.16.43.1/'   /etc/unudhcpd.conf
sudo sed -i 's/^unudhcpd_client_ip=.*/unudhcpd_client_ip=172.16.43.2/' /etc/unudhcpd.conf
sudo mkinitfs          # REQUIRED - without this the change is ignored
sudo reboot
```

Planned allocation (mirrored in Doppler `PIXEL3A*_USB_IP` /
`PIXEL3A*_HOST_USB_IP`):

| Phone | Phone IP | Proxmox side |
|---|---|---|
| `pixel3a1` | 172.16.41.1 | 172.16.41.2 |
| `pixel3a2` | 172.16.42.1 | 172.16.42.2 |
| `pixel3a3` | 172.16.43.1 | 172.16.43.2 |

## Host side (Proxmox)

The phones reach the cluster *through* the Proxmox host, so it must forward and
NAT for them, and the API server must be able to reach back for `kubectl logs`
and `exec`.

```sh
# forwarding
sysctl -w net.ipv4.ip_forward=1
echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/99-phone-nodes.conf

# NAT each USB subnet out to the LAN (replace vmbr0 with the real uplink)
for n in 41 42 43; do
  iptables -t nat -C POSTROUTING -s 172.16.$n.0/24 -o vmbr0 -j MASQUERADE 2>/dev/null \
    || iptables -t nat -A POSTROUTING -s 172.16.$n.0/24 -o vmbr0 -j MASQUERADE
done
```

Then, so the control plane can reach the kubelets, give **LXC 200** a route back
per subnet via the Proxmox host:

```sh
pct exec 200 -- ip route add 172.16.41.0/24 via <proxmox-lan-ip>
pct exec 200 -- ip route add 172.16.42.0/24 via <proxmox-lan-ip>
pct exec 200 -- ip route add 172.16.43.0/24 via <proxmox-lan-ip>
```

Without those return routes the node registers and then goes `NotReady`, and
`kubectl logs` against it times out — the agent's outbound connection works
while nothing can reach the kubelet on :10250.

## Joining

Everything is pre-staged on `pixel3a2`: matching **k3s v1.31.5+k3s1** binary at
`/usr/local/bin/k3s` (agent version must match the server), the node token at
`/etc/rancher/k3s/node-token` (0600), and:

```sh
sudo /usr/local/bin/join-cluster.sh
```

It verifies clock, cgroup2 + memory controller, modules, binary, token, and
**API reachability** before installing an OpenRC service and starting the agent.
Each precondition fails loudly with its own message rather than hanging, which
is the whole point — a k3s agent that cannot reach its server just retries
silently forever.

Override the defaults with `K3S_SERVER` / `NODE_NAME` env vars.

## Known limitation: NetworkPolicy

`CONFIG_IP_SET` is **missing** from this kernel. kube-router needs ipset to
enforce NetworkPolicies, and this cluster uses them heavily. Expect policies to
go unenforced for pods scheduled onto these nodes.

Until that is confirmed one way or the other, prefer taints/affinity so only
workloads that do not depend on NetworkPolicy land here:

```sh
kubectl taint nodes pixel3a2 arch=phone:NoSchedule
```

## Status

- `pixel3a2` — **fully staged**; join blocked only on being on the home network
- `pixel3a1` — not yet reachable (link up, no IPv4; needs the subnet change above)
- `pixel3a3` — untouched; has working WiFi so it can join without USB
