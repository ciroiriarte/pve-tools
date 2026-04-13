# pve-tools

Operational scripts for [Proxmox VE](https://www.proxmox.com/en/proxmox-virtual-environment) clusters.

## Contents

- [pve-import-cloud-images](#pve-import-cloud-images) - Import upstream cloud images as PVE templates
  - [Cloud-init usage](cloud-init-usage.md) - Provisioning examples and sample snippets
- [pve-vmnic-fix](#pve-vmnic-fix) - Repair VM/CT network bridges after host network changes
- [pve-create-tshoot-image](#pve-create-tshoot-image) - Build a ReaR troubleshooting / restore ISO
- [pve-sdn-healthcheck](#pve-sdn-healthcheck) - Validate the SDN network layer (underlay + overlay)
- [pve-rolling-upgrade](#pve-rolling-upgrade) - Rolling, health-gated PVE 8→9 upgrade of one node
- [pve-ceph-upgrade](#pve-ceph-upgrade) - Online Ceph major-release migration (e.g. Squid→Tentacle)
- [Installation](#installation)
- [License](#license)

---

## pve-import-cloud-images

Import upstream cloud images as PVE templates ready for cloning with cloud-init.

Dynamically scans distribution mirrors to discover the latest releases — no hardcoded URLs.

**Supported distributions** (last two releases each):

| Family | Mirror | Customization |
|---|---|---|
| Debian | cdimage.debian.org | qemu-guest-agent |
| Ubuntu LTS | cloud-images.ubuntu.com | qemu-guest-agent |
| Rocky Linux | dl.rockylinux.org | v10 requires x86-64-v3 |
| openSUSE Leap | download.opensuse.org | ptp_kvm module |
| Oracle Linux | yum.oracle.com | v10 requires x86-64-v3 |
| FreeBSD | download.freebsd.org | VM notes with install instructions |

**Usage:**

```bash
# List what's available (no root needed)
pve-import-cloud-images --list

# Interactive selection (local mode on a PVE node)
pve-import-cloud-images --mode local

# Import all images
pve-import-cloud-images --mode local --batch

# Import only Debian templates to a specific storage
pve-import-cloud-images --mode local --batch --distro debian --storage ceph-pool

# Preview without making changes
pve-import-cloud-images --mode local --dry-run --batch
```

**Per-image workflow:**

1. Download cloud image (cached in `/var/tmp/pve-cloud-images/`)
2. Probe image for precise OS version via `virt-cat` (e.g. Debian 12 → 12.13)
3. Optionally inject `qemu-guest-agent` via `virt-customize`
4. Create VM with EFI, virtio-scsi, serial console, cloud-init drive
5. Import disk and convert to template

**EL10 / x86-64-v3 requirement:**

Rocky Linux 10 and Oracle Linux 10 (RHEL 10-based) require x86-64-v3 (Haswell or newer). VMs will fail to boot on hosts with older CPUs (e.g. Ivy Bridge, Sandy Bridge). Verify your host supports v3 before importing these images:

```bash
/lib/ld-linux-x86-64.so.2 --help 2>&1 | grep supported
# or check for AVX2: grep -q avx2 /proc/cpuinfo && echo v3 || echo v2
```

**FreeBSD guest agent:**

FreeBSD images cannot be customized offline (Linux cannot write to UFS2 filesystems), so `qemu-guest-agent` must be installed after first boot:

```bash
pkg install -y qemu-guest-agent
sysrc qemu_guest_agent_enable=YES
service qemu-guest-agent start
```

To automate this via cloud-init, copy [`samples/ci-user-freebsd.yaml`](samples/ci-user-freebsd.yaml) to a snippets-enabled storage and apply it to the VM:

```bash
cp samples/ci-user-freebsd.yaml /var/lib/vz/snippets/
qm set <vmid> --cicustom "user=local:snippets/ci-user-freebsd.yaml"
qm cloudinit update <vmid>
qm start <vmid>
```

> **Note:** FreeBSD uses `nuageinit` instead of Python cloud-init. It does not read `vendor-data`, so `cicustom user=` is required — which replaces PVE's auto-generated user-data. The snippet must include all settings (SSH keys, users, etc.); hostname is set by PVE via the VM name and does not need to be in the snippet.

See [cloud-init-usage.md](cloud-init-usage.md) for full provisioning documentation.

**API mode:**

The script can run remotely (no SSH required) using the PVE REST API:

```bash
pve-import-cloud-images --mode api \
    --api-host https://pve.example.com:8006 \
    --api-node pve1 \
    --api-token 'user@pam!tokenid=secret-uuid' \
    --batch --storage local-zfs
```

All VM operations (create, disk import, template conversion) are performed via
API calls.  The only local dependency is `curl`.

**API mode pre-requirements:**

1. **Create an API token** on the PVE host (Datacenter → Permissions → API Tokens,
   or via CLI):

   ```bash
   pveum user token add root@pam cloudimport --privsep 0
   ```

   The `--privsep 0` flag disables privilege separation so the token inherits
   the user's permissions.  Copy the displayed token value — it is shown only
   once.  The token format for `--api-token` is `user@realm!tokenid=secret`.

2. **Create the vendor-data snippet** for automatic guest-agent installation on
   Linux templates.  The PVE upload API does not support snippets, so this file
   must be created once directly on the storage:

   ```bash
   # On the PVE host — adjust the path for your snippets-enabled storage
   cat > /mnt/pve/YOUR-STORAGE/snippets/ci-qemu-guest-agent-vendor.yaml << 'EOF'
   #cloud-config
   package_update: true
   packages:
     - qemu-guest-agent
   runcmd:
     - systemctl enable --now qemu-guest-agent
   EOF
   ```

   If the snippet is missing, the script still creates templates but skips
   the `cicustom` vendor-data configuration and prints instructions.

**Dependencies (local mode):** `qm`, `qemu-img`, `wget` or `curl`. Optional: `libguestfs-tools` (for guest-agent injection), `xz` (for FreeBSD images).

**Dependencies (API mode):** `curl` only. No SSH access or local PVE tools required.

---

## pve-vmnic-fix

Repair VM/CT network bridges after host network changes (e.g. applying pending network config, restarting networking, or SDN reload).

**What it fixes:**

- tap/veth interfaces losing their bridge master
- Firewall intermediary links (fwbr/fwpr/fwln) going DOWN
- EVPN not learning guest MACs after bridge reset

**Usage:**

```bash
# Fix a single guest
pve-vmnic-fix 100

# Fix all running VMs and containers
pve-vmnic-fix --all

# Preview changes
pve-vmnic-fix --dry-run --all
```

Reports per-interface status and prints a summary:

```
:: Fixing vm 100
   Checking net0 (bridge: vmbr0)...
   [+] net0 OK
:: Done. 1 guest(s), 1 interface(s) checked, 0 repaired.
```

---

## pve-create-tshoot-image

Build a [ReaR](https://relax-and-recover.org/) troubleshooting / restore ISO from a PVE cloud-init template.

The ISO boots into a rescue environment pre-loaded with network diagnostic tools. It identifies the physical host via DMI serial number and applies per-host identity (hostname + IP) from a CSV inventory.

**Modes of operation:**

| Mode | Where to run | ISO destination | Requirements |
|---|---|---|---|
| **Local** | Directly on a PVE node (as root) | PVE node filesystem | PVE tools + libguestfs + python3 |
| **Remote** | From a jump host (`-S user@host`) | Jump host filesystem | `ssh` + `scp` only |

In remote mode the script copies itself and the CSV to the PVE node, builds the ISO there, then downloads it back to the jump host.

**On boot the ISO will:**

1. Read the system serial number → set hostname and management IP from CSV
2. Bring up **every** physical NIC and start lldpd for neighbour discovery (unconditional — runs even without IP configuration)
3. (Optional) Configure a bonded VLAN management interface with per-host IP
4. Present `tcpdump`, `nic-xray` and `lldpcli` for network diagnostics
5. Offer `rear recover` to deploy the base OS to local disks

The build VM is an intermediate state — host identity files (`machine-id`, SSH host keys, `random-seed`) are wiped so each restored system is unique.

**Supported distributions:**

| Family | Package manager | Extras |
|---|---|---|
| Rocky Linux (8, 9) | dnf + EPEL | nic-xray from OBS |
| Ubuntu LTS (22.04, 24.04) | apt | nic-xray from OBS |
| openSUSE Leap (15.x, 16.x) | zypper | nic-xray from OBS |

**Usage:**

```bash
# Local mode — run on a PVE node, ISO saved to current directory
pve-create-tshoot-image -t 9000 -c hosts.csv

# Local mode — ISO to a specific directory
pve-create-tshoot-image -t 9000 -c hosts.csv -o /var/tmp/iso/

# Remote mode — build on a PVE node, ISO downloaded to jump host
pve-create-tshoot-image -t 9000 -c hosts.csv -S root@pve1.example.com

# With VLAN management network (either mode)
pve-create-tshoot-image -t 9000 -c hosts.csv \
    --vlan-id 100 --netmask /24 --gateway 10.0.0.1 --dns 8.8.8.8

# Build VM on a different VLAN with HTTP proxy
pve-create-tshoot-image -t 9000 -c hosts.csv \
    --vm-vlan 302 --vm-proxy http://proxy:3128

# Rescue-only (smaller ISO, no backup)
pve-create-tshoot-image -t 9000 -c hosts.csv --rescue-only
```

**CSV file** (host inventory — serial, hostname, bond members, management IP):

```csv
# serial,hostname,bond_members,ip
SVR001,web-server-01,eth0:eth1,10.0.0.11
SVR002,db-server-01,eno1:eno2,10.0.0.12
SVR003,app-server-01,ens1f0:ens1f1,10.0.0.13
```

Bond members use `:` as separator to allow for different hardware across servers.

**Target-host network** (CLI parameters, shared across all hosts):

| Parameter | Description | Default |
|---|---|---|
| `--bond-mode` | Bonding mode | `802.3ad` |
| `--vlan-id` | Management VLAN ID | *(no VLAN)* |
| `--netmask` | Network mask (e.g. `/24`) | *(required with --gateway/--dns)* |
| `--gateway` | Default gateway | *(required with --netmask/--dns)* |
| `--dns` | Comma-separated DNS servers | *(required with --netmask/--gateway)* |
| `--proxy` | HTTP/HTTPS proxy for restored hosts | *(optional)* |

Per-host IP and bond members come from the CSV (allowing different hardware per server). The shared parameters above define how the management interface is constructed (bond → VLAN → IP assignment).

**Build-VM network** (used only during image preparation):

| Parameter | Description | Default |
|---|---|---|
| `--vm-bridge` | PVE bridge | `vmbr0` |
| `--vm-vlan` | VLAN tag on the build VM NIC | *(none)* |
| `--vm-ip` | Build VM IP (`dhcp` or `IP/MASK`) | `dhcp` |
| `--vm-gateway` | Gateway (required if static) | |
| `--vm-dns` | DNS (optional for static) | |
| `--vm-proxy` | HTTP/HTTPS proxy for build VM | *(optional)* |

All VM interaction uses the QEMU guest agent (virtio serial channel) — no network connectivity is required between the PVE host and the build VM.  This allows building on any VLAN regardless of L3 routing.

**Workflow:**

1. Clone the specified PVE template to a temporary VM (full clone)
2. Detect the distribution from the disk image (`/etc/os-release`)
3. Resize disk (+10G), inject config files via `virt-customize`, wipe host identity, enable guest-exec
4. Boot the VM (cloud-init grows the filesystem), install packages via QEMU guest agent
5. Run `rear mkbackup` (or `rear mkrescue` with `--rescue-only`) via guest agent
6. Stop the VM, extract the ISO via `virt-copy-out`, destroy the temporary VM

**Dependencies (local mode):** `qm`, `pvesm`, `pvesh`, `virt-customize`, `virt-cat`, `virt-copy-out`, `python3`.

**Dependencies (remote mode):** `ssh` and `scp` only (PVE tools are used on the remote node).

---

## pve-sdn-healthcheck

Validate the entire network layer of a Proxmox VE + FRR/BGP-EVPN/VXLAN cluster
— underlay **and** overlay — in one read-only command.

Connects to every node over SSH, runs underlay and overlay checks on each, and
aggregates them into a fail-first report with a single cluster-wide verdict and
Nagios exit codes (for LibreNMS / Zabbix / Icinga / CI).

**Portable by design** — every site-specific entity (node list, VTEP peers, L3
VNIs/VRFs, external BGP peers) is auto-discovered from the live system, so it
runs unmodified on any cluster. Non-SDN nodes are detected and their
overlay/forwarding checks are skipped rather than failed.

**Checks**

| Layer | Checks |
|---|---|
| Underlay | ip_forward (runtime + persistence), FRR daemon, link state, NIC errors/drops, link flapping, SFP/QSFP optic DOM, bond/LACP, MTU headroom, BGP-EVPN fabric, per-VRF external peering (v4+v6), VTEP reachability, Ceph net |
| Overlay | L2/L3 VNIs (control vs kernel), EVPN routes, anycast-gateway/IRB, L3-VNI FDB (black-hole vs benign on-demand), RIB/FIB consistency |
| Plumbing | Guest NIC chain `tap/veth → fwbr/fwpr/fwln → vnet` intact (mirrors `pve-vmnic-fix`) |

**Usage:**

```bash
# Check the whole cluster (auto-discovered nodes)
pve-sdn-healthcheck

# Two nodes, overlay only, show every check (not just WARN/FAIL)
pve-sdn-healthcheck --node pve01,pve02 --only overlay --all

# Explain a check (what it validates / why / how WARN vs FAIL)
pve-sdn-healthcheck --explain l3vni_fdb

# Feed monitoring
pve-sdn-healthcheck --json | jq .counts

# From a non-member management host, via a jump host
SDN_NODES='root@10.0.0.4 root@10.0.0.10' \
  SDN_SSH_OPTS='-J admin@jump.example' pve-sdn-healthcheck
```

**Safe auto-remediation (opt-in):** `--fix` previews, `--apply` executes
(root, logged to `/var/log/pve-sdn-healthcheck-fix.log`). The allow-list is
limited to safe, idempotent repairs — `ip_forward` (set + persist),
`vmnic_plumbing` (delegates to `pve-vmnic-fix`), and `frr_daemon` (enable at
boot). BGP/EVPN, zebra/FRR restarts, MTU, optics and bonding are **never**
auto-fixed.

```bash
pve-sdn-healthcheck --fix                       # preview
pve-sdn-healthcheck --fix ip_forward --apply    # apply (asks to confirm)
```

**Configuration:** everything auto-discovers; optional overrides
(`SDN_NODES`, `SDN_SSH_OPTS`, `SDN_FW_MASTER`/`SDN_FW_BACKUP`, `SDN_L3VNIS`,
`SDN_VTEPS`, `SDN_MTU_DELTA`, `SDN_VRF_PROBES`) may be set in the environment or
in `/etc/pve-sdn-healthcheck.conf`. Setting `SDN_VRF_PROBES="<vrf>:<ip>"`
upgrades the L3-VNI check from a cautious WARN to a definitive PASS/FAIL via a
data-plane probe.

**Exit codes:** `0` OK · `1` WARN · `2` CRIT (FAIL) · `3` UNKNOWN (usage error
or unreachable node).

**Dependencies:** controller needs `bash` and `ssh`; each node needs `vtysh`
(FRR), `ip`/`bridge`, `sysctl`. Optional and used when present: `ethtool`,
`jq`, `journalctl`, `pve-vmnic-fix`.

---

## pve-rolling-upgrade

Rolling, health-gated **Proxmox VE 8 → 9** upgrade (Debian Bookworm → Trixie) of **one cluster node at a time**, **without shutting guests down**.

For each node it live-migrates every running guest off (HA-aware), rewrites the APT repos `bookworm → trixie`, runs the `dist-upgrade`, pins NIC names, hardens the boot path, reboots, and only declares success once a full health gate passes. It **hard-stops on any failed gate** so a problem halts at that node instead of cascading.

**Portable by design** — stable peer, migration targets, mon-quorum size, target kernel, which repo files carry `bookworm`, and FRR/EVPN presence are all auto-discovered from the live cluster.

**Per-node sequence (each step gated):**

| Step | Action |
|---|---|
| pre-gate | Ceph all-PGs `active+clean` + cluster quorate |
| drain | live-migrate every guest off (HA via `ha-manager`), wait until empty |
| stage | repos `bookworm→trixie` (third-party only if a `trixie` suite exists), clean `apt update`, then `dist-upgrade` |
| boot-prep | disable the re-added enterprise repo, install an rp_filter service (EVPN), pin NIC names, rebuild initramfs + boot |
| reboot | boot_id-gated; wait for the node to return on the new kernel |
| post-gate | NIC names as expected, FRR/EVPN up, Ceph `active+clean`, mon quorum restored, cluster quorate |

**Usage:**

```bash
# Preview (read-only discovery, no changes) through a bastion
pve-rolling-upgrade --dry-run -j root@bastion 192.168.0.14

# Upgrade one node (keeps original eno*/ens5f* NIC names by default)
pve-rolling-upgrade -j root@bastion 192.168.0.14

# Use the PVE nicN naming scheme instead of keeping original names
pve-rolling-upgrade --nic-pin pmx pve04
```

Run it **one node at a time, in order — non-mon nodes first, the mon leader last** — re-checking cluster health between nodes.

**NIC naming:** `--nic-pin keep` (default) pins the *current* names (`eno*/ens5f*`) by permanent MAC, so the systemd naming-scheme change across the major jump cannot rename the EVPN/corosync underlay. `--nic-pin pmx` uses `pve-network-interface-pinning` (renames to the `nicN` scheme).

> **Pre-conditions** (asserted by you, not the tool): every node already on the latest 8.4; Ceph (if hyper-converged) already on the PVE 9 release; `noout` set for the window; cluster healthy bar the `noout` warning; and console/IPMI access in case a reboot mis-names a NIC. **It reboots the node — production, hard-to-reverse.**

**Configuration:** optional overrides via env or `/etc/pve-rolling-upgrade.conf` — `PVE_RU_SSH_OPTS` (e.g. ProxyJump/IdentityFile), `PVE_RU_JUMP`, `PVE_RU_KEEP_NIC_NAMES`, `PVE_RU_TARGET_KERNEL`, `PVE_RU_VENDOR_HEALTH`.

**Exit codes:** `0` OK · `1` FAIL (a gate failed; run halted) · `2` usage/dependency error.

**Dependencies:** controller needs `bash` and `ssh`; each node needs the PVE stack (`qm`, `pvecm`, `ceph`, `proxmox-boot-tool`) and `ethtool`. FRR/EVPN checks run only when FRR is present. Key-based root SSH to every node (directly or via `--jump`) is assumed.

---

## pve-ceph-upgrade

Online **Ceph major-release migration** (e.g. **Squid 19 → Tentacle 20**) for a PVE hyper-converged cluster, with **no guest downtime**.

The Ceph-major counterpart to [pve-rolling-upgrade](#pve-rolling-upgrade): that tool does the PVE 8→9 *distro* jump and leaves Ceph alone; this one does the *Ceph* major and leaves the Debian/PVE release alone. **Run them as separate passes — never combine a Ceph major with a distro upgrade.**

It stages the new packages everywhere, then restarts daemons in the upstream-mandated order — **monitor → manager → OSD → MDS** — gating on Ceph health and quorum between every step, and only flips `require-osd-release` once every OSD is on the new release. Topology (mon/mgr/OSD/MDS placement, CephFS name + standby-replay, source release) is auto-discovered.

**Per-step sequence (each gated):**

| Step | Action |
|---|---|
| preflight | target repo exists; cluster on PVE 9; HEALTH ok; all daemons on `<from>`; active+clean; quorate |
| stage | `ceph osd set noout`; per node bump repo `ceph-<from>→ceph-<to>`, `apt update`, install Ceph (daemons keep `<from>` until restarted) |
| mons | restart `ceph-mon` one node at a time; wait full quorum |
| mgrs | restart `ceph-mgr` (active fails over) |
| osds | restart OSDs one node at a time; wait `active+clean` (`noout` avoids rebalance churn) |
| mds | (CephFS) disable standby-replay, restart standbys then active, restore |
| finalize | `ceph osd require-osd-release <to>`; `ceph osd unset noout`; verify every daemon on `<to>` + HEALTH ok |

**Usage:**

```bash
# Preview a Squid→Tentacle migration (read-only)
pve-ceph-upgrade --dry-run --to tentacle -j root@bastion -s pve01

# Perform it (asks to confirm; -y for unattended)
pve-ceph-upgrade --to tentacle -j root@bastion -s pve01
```

> **Pre-conditions:** the cluster must already be fully on PVE 9, `HEALTH_OK` (bar `noout`), every daemon on the source release, all PGs `active+clean`, and quorate. **Read the version-specific upstream notes first** — `https://pve.proxmox.com/wiki/Ceph_<From>_to_<To>` — the exact daemon order and any pre-steps are release-specific. **A Ceph major is one-way once `require-osd-release` is set.**

**Configuration:** optional overrides via env or `/etc/pve-ceph-upgrade.conf` — `PVE_CU_SSH_OPTS`, `PVE_CU_JUMP`, `PVE_CU_REPO_BASE`.

**Exit codes:** `0` OK · `1` FAIL (a gate failed; run halted) · `2` usage/dependency error.

**Dependencies:** controller needs `bash`, `ssh`, `curl`; each node needs the Ceph/PVE stack (`ceph`, `systemctl`, `apt`). Node names from `pvecm nodes` must be reachable from the controller (directly or via `--jump`). Key-based root SSH assumed.

---

## Installation

Two methods are supported. The **`.deb` package** is recommended on a real PVE
node (clean upgrades and removal via `apt`); the **manual copy** is handy for a
quick try-out or air-gapped hosts.

### Method 1 — Debian package (recommended)

Pre-built `.deb` packages are published from the [openSUSE Build
Service](https://build.opensuse.org) and built directly from this repository's
tagged releases. PVE 8 runs on Debian 12 (Bookworm), PVE 9 on Debian 13
(Trixie) — pick the matching line below.

```bash
# --- PVE 8 / Debian 12 (Bookworm) --------------------------------------------
REPO=https://download.opensuse.org/repositories/home:/ciriarte:/pve-tools/Debian_12

# --- PVE 9 / Debian 13 (Trixie) ----------------------------------------------
# REPO=https://download.opensuse.org/repositories/home:/ciriarte:/pve-tools/Debian_13

# Trust the repository signing key and register the repo
curl -fsSL "$REPO/Release.key" | gpg --dearmor -o /usr/share/keyrings/pve-tools.gpg
echo "deb [signed-by=/usr/share/keyrings/pve-tools.gpg] $REPO/ /" \
  > /etc/apt/sources.list.d/pve-tools.list

apt update && apt install pve-tools
```

This installs the six scripts to `/usr/sbin`, their man pages to
`/usr/share/man/man8`, and the bash completion to
`/usr/share/bash-completion/completions`. Updates then arrive with the usual
`apt upgrade`. To install a single `.deb` without adding the repo, download it
from the `Debian_12/all/` (or `Debian_13/all/`) directory and run
`apt install ./pve-tools_*.deb`.

### Method 2 — Manual copy

Copy the desired script(s) to a directory in your `PATH` on each PVE node:

```bash
cp pve-import-cloud-images pve-vmnic-fix pve-create-tshoot-image pve-sdn-healthcheck pve-rolling-upgrade pve-ceph-upgrade /usr/local/sbin/
```

Man pages are provided in `man/man8/`. To install them:

```bash
cp man/man8/*.8 /usr/local/share/man/man8/
```

Bash completions are provided in `completions/`. To install them:

```bash
cp completions/pve-tools.bash /etc/bash_completion.d/pve-tools
```

### Building the package

Debian packaging lives in [`packaging/debian/`](packaging/debian/). The OBS
project sources this repository over plain git, tracks new release tags, and
rebuilds the `.deb` automatically — no tarball is committed. To build locally
instead, expose the packaging as a top-level `debian/` and build:

```bash
ln -s packaging/debian debian
dpkg-buildpackage -us -uc -b
```

## License

MIT
