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

# Interactive selection (default on TTY)
pve-import-cloud-images

# Import all images
pve-import-cloud-images --batch

# Import only Debian templates to a specific storage
pve-import-cloud-images --batch --distro debian --storage ceph-pool

# Preview without making changes
pve-import-cloud-images --dry-run --batch
```

**Per-image workflow:**

1. Download cloud image (cached in `/var/tmp/pve-cloud-images/`)
2. Optionally inject `qemu-guest-agent` via `virt-customize`
3. Create VM with EFI, virtio-scsi, serial console, cloud-init drive
4. Import disk and convert to template

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

## Installation

Copy the desired script(s) to a directory in your `PATH` on each PVE node:

```bash
cp pve-import-cloud-images pve-vmnic-fix /usr/local/sbin/
```

## License

MIT
