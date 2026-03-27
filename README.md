# pve-scripts

Operational scripts for [Proxmox VE](https://www.proxmox.com/en/proxmox-virtual-environment) clusters.

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

To automate this via cloud-init, create a user-data snippet on a snippets-enabled storage (e.g. `local:snippets/freebsd-agent.yml`):

```yaml
#cloud-config
hostname: my-freebsd-vm
ssh_authorized_keys:
  - ssh-rsa AAAA... user@host
users:
  - default
packages:
  - qemu-guest-agent
runcmd:
  - sysrc qemu_guest_agent_enable=YES
  - service qemu-guest-agent start
```

Then apply it to the VM:

```bash
qm set <vmid> --cicustom "user=local:snippets/freebsd-agent.yml"
```

> **Note:** FreeBSD uses `nuageinit` instead of Python cloud-init. It does not read `vendor-data`, so `cicustom user=` is required — which replaces PVE's auto-generated user-data. The snippet must include all cloud-init settings (hostname, SSH keys, users, etc.).

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

## Installation

Copy the desired script(s) to a directory in your `PATH` on each PVE node:

```bash
cp pve-import-cloud-images pve-vmnic-fix pve-create-tshoot-image /usr/local/sbin/
```

## License

MIT
