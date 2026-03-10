# pve-scripts

Operational scripts for [Proxmox VE](https://www.proxmox.com/en/proxmox-virtual-environment) clusters.

## Scripts

### pve-import-cloud-images

Import upstream cloud images as PVE templates ready for cloning with cloud-init.

Dynamically scans distribution mirrors to discover the latest releases — no hardcoded URLs.

**Supported distributions** (last two releases each):

| Family | Mirror | Customization |
|---|---|---|
| Debian | cdimage.debian.org | qemu-guest-agent |
| Ubuntu LTS | cloud-images.ubuntu.com | qemu-guest-agent |
| Rocky Linux | dl.rockylinux.org | — |
| openSUSE Leap | download.opensuse.org | ptp_kvm module |
| Oracle Linux | yum.oracle.com | — |
| FreeBSD | download.freebsd.org | — |

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

**Dependencies:** `qm`, `qemu-img`, `wget` or `curl`. Optional: `libguestfs-tools` (for guest-agent injection), `xz` (for FreeBSD images).

### pve-vmnic-fix

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

## Installation

Copy the desired script(s) to a directory in your `PATH` on each PVE node:

```bash
cp pve-import-cloud-images pve-vmnic-fix /usr/local/sbin/
```

## License

MIT
