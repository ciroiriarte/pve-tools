# pve-tools

Operational scripts for [Proxmox VE](https://www.proxmox.com/en/proxmox-virtual-environment) clusters.

## Contents

- [pve-import-cloud-images](#pve-import-cloud-images) - Import upstream cloud images as PVE templates
  - [Cloud-init usage](cloud-init-usage.md) - Provisioning examples and sample snippets
- [pve-vmnic-fix](#pve-vmnic-fix) - Repair VM/CT network bridges after host network changes
- [pve-build-windows-template](#pve-build-windows-template) - Build sysprepped Windows Server templates unattended
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

## pve-build-windows-template

Turn a Windows Server ISO into sysprepped, cloud-init-capable PVE templates in one non-interactive run. No console interaction at any point — no clicking through Setup, no hunting for the virtio driver at disk selection, no manual sysprep.

By default a single invocation produces **two** templates — Server Core and Desktop Experience — at consecutive VMIDs.

The output is a genuine template rather than a golden disk: [Cloudbase-Init](https://cloudbase.it/cloudbase-init/) is installed and configured against the PVE cloud-init drive, so a clone picks up its hostname, network configuration, administrator password and SSH keys on first boot, exactly as a Linux clone does.

**Modes of operation:**

| Mode | Where to run | Where the template lands | Requirements |
|---|---|---|---|
| **Local** | Directly on a PVE node (as root) | That node | PVE tools + genisoimage + wimtools + libguestfs |
| **Remote** | From a jump host (`-S user@host`) | The remote node | `ssh` + `scp` only |

In remote mode the script copies itself to the node and re-executes there. Nothing is downloaded back — the template stays on the node — and all paths (`--iso`, `--cache-dir`) are interpreted **remotely**. Secrets travel as mode-0600 files, never as arguments, so they never appear in the remote process table.

### Licensing

The script **never** downloads, caches or redistributes Windows media or a licence key. You supply the ISO with `--iso`. The single exception is opt-in: `--eval 2019|2022|2025` downloads Microsoft's freely-redistributable 180-day evaluation media from the Microsoft Evaluation Center.

Only the redistributable payloads — the virtio-win driver ISO, the SPICE agent MSI and Cloudbase-Init — are fetched automatically, and each can be overridden with `--virtio-iso`, `--spice-msi` and `--cloudbase-msi` for air-gapped sites.

Product keys never appear in `--dry-run` output, in diagnostics, or in any process table.

**Supported matrix:**

| Release | `ostype` | Server Core | Desktop Experience | Standard | Datacenter |
|---|---|---|---|---|---|
| Windows Server 2019 | `win10` | yes | yes | yes | yes |
| Windows Server 2022 | `win11` | yes | yes | yes | yes |
| Windows Server 2025 | `win11` | yes | yes | yes | yes |

x86_64 and UEFI/GPT only. PVE has no `win2k19`/`win2k22` ostype — `win10` covers 2016/2019 and `win11` covers 2022/2025.

### Language support

**Any Windows Server localisation works** — English, Spanish, Russian, Japanese and so on — with no extra arguments. Three things make that true:

- **Edition selection is language-invariant.** The script matches the WIM `Name` field, which Microsoft does not localise: Spanish media still reports `Windows Server 2025 SERVERSTANDARDCORE`. (Verified against `es-MX` media — the localised strings live in `Display Name`, which the script deliberately ignores.)
- **The release is detected from the NT build number** (`17763` → 2019, `20348` → 2022, `26100` → 2025), not from an English product string. `--release` overrides it.
- **`--locale` defaults to the media's own language**, read from the WIM `Default Language`. `SetupUILanguage` has to name a language that exists on the media, so an `en-US` default would break every non-English ISO. Pass `--locale` only to override, and `--input-locale` if the keyboard layout should differ from the system locale. If you pass a `--locale` the media does not carry, the script warns before building rather than letting Setup stall on the language page.

**`--eval` covers only the eight languages Microsoft publishes evaluation media in**: `en-US`, `fr-FR`, `es-ES`, `de-DE`, `it-IT`, `ja-JP`, `ru-RU`, `zh-CN`. Anything else — `ko-KR` and `zh-TW` among them — is rejected with a message naming the alternatives, because the Evaluation Center answers an unrecognised `clcid` with the **English** ISO and an HTTP 200, giving no sign of the substitution. Building on that would produce an English template labelled Korean. Use `--iso` with media you supply for those languages. As a second line of defence, when `--eval` media comes back in a different language from the one requested, the build stops rather than continuing.

The Remote Desktop firewall rule is enabled through the `@FirewallAPI.dll,-28752` indirect reference rather than the display name `"Remote Desktop"`, which is localised and would not match on a non-English install.

One caveat: `groups=Administrators` in the Cloudbase-Init config is a literal group name. It only comes into play when `--ci-username` names an account that does not already exist, and on a localised Windows the local group is `Administradores`, `Администраторы`, and so on. The default `--ci-username Administrator` is already a member of the group, so the common path is unaffected.

**Usage:**

```bash
# Core + Desktop Standard templates from your own ISO
pve-build-windows-template --iso dstore01:iso/win2022.iso --storage dstore01

# Evaluation media, Datacenter, Core only, built on an uplink-less bridge
pve-build-windows-template --eval 2025 --sku datacenter --edition core \
    --storage dstore01 --build-bridge vmbr1 --start-id 9040

# Licensed media activated against KMS
pve-build-windows-template --iso /mnt/iso/win2022-vl.iso --kms --storage dstore01

# Remote build from a jump host (paths are remote)
pve-build-windows-template --iso dstore01:iso/win2022.iso --storage dstore01 \
    -S root@pve1.example.com

# Print the full plan and touch nothing
pve-build-windows-template --iso dstore01:iso/win2022.iso --storage dstore01 --dry-run
```

**Key parameters:**

| Parameter | Description | Default |
|---|---|---|
| `-i, --iso PATH` | Windows ISO — path or `STORAGE:iso/NAME`. Never auto-downloaded | *(required unless `--eval`)* |
| `--eval RELEASE` | Download Microsoft 180-day evaluation media (`2019`/`2022`/`2025`) | off |
| `-e, --edition WHICH` | `core` \| `desktop` \| `both` | `both` |
| `-k, --sku SKU` | `standard` \| `datacenter` | `standard` |
| `-R, --release REL` | `2019` \| `2022` \| `2025` | auto-detected from the media |
| `-s, --storage NAME` | Storage for VM disks | `local-lvm` |
| `--iso-storage NAME` | Storage for downloaded/generated ISOs (must accept `iso`) | `--storage` |
| `-I, --start-id ID` | First VMID; one per edition, consecutive | `9020` |
| `-B, --bridge NAME` / `--vlan TAG` | Template NIC placement | `vmbr0` |
| `--build-bridge NAME` | Bridge for the build VM — an uplink-less one is recommended | `--bridge` |
| `-D, --disk-size GB` | OS disk size | `60` |
| `--product-key KEY` / `--kms` | Activation; omitting both is valid (deferred activation) | none |
| `--kms-host HOST[:PORT]` | Point clones at a KMS server and let Cloudbase-Init activate them | none |
| `--locale TAG` / `--input-locale TAG` | System locale / keyboard layout | the media's own language |
| `--admin-password PW` | Administrator password | random, printed once |
| `--no-tpm` / `--no-secureboot` | Drop the TPM 2.0 volume / pre-enrolled Secure Boot keys | both on |
| `--no-rdp` | Do not enable Remote Desktop in the template | RDP enabled |
| `--addons DIR` / `--addon DIR` | Install operator-supplied software into the template (repeatable). See **Addons** below | none |
| `--keep-on-failure` | Leave the build VM in place for inspection | off |
| `-m, --mode`, `-S, --server` | Local vs. remote execution | local |
| `--dry-run`, `--help`, `--version` | Repo-wide conventions | — |

**Workflow:**

1. Resolve the Windows media, virtio-win ISO, Cloudbase-Init MSI and SPICE agent MSI, caching each under the ISO storage
2. Mount the Windows media (UDF) and read the image list with `wiminfo` — auto-detect the release, detect evaluation media, resolve the exact `/IMAGE/NAME` for the requested SKU and edition
3. Flatten the release-specific virtio drivers and stage **every** in-guest payload onto a generated answer ISO — the build VM needs no network access at all
4. Create the build VM (`ovmf` + `q35` + `virtio-scsi-single` + TPM 2.0 + Secure Boot) and start it
5. Wait for Setup, then for payload installation reported through the QEMU guest agent, then for sysprep's own shutdown
6. Verify offline that `Sysprep_succeeded.tag` exists on the disk, detach every CD-ROM, attach the cloud-init drive, `qm template`

Everything installed in the guest — virtio drivers, QEMU guest agent, SPICE agent and Cloudbase-Init — is staged from the host onto the answer ISO. The build VM never downloads anything, so an air-gapped node builds exactly the same template as a connected one.

**Template naming:** `ci-win<release>-<std|dc>-<core|desktop>-<locale>-<timestamp>.x86-64`, for example `ci-win2025-std-core-ja-jp-202608051603.x86-64`. The locale is part of the name because without it two localisations of the same release, SKU and edition differ only by `<timestamp>`, which has minute resolution and is taken once per run — so two builds started in the same minute produce identical names. The locale is also recorded in the template description alongside the release, WIM image, source ISO and payload versions.

Remote Desktop is enabled with its firewall rule as part of step 5 (`--no-rdp` to skip). Each in-guest installer runs under its own timeout, so a hung installer degrades to a warning instead of stalling the build; progress is reported live from the guest through the QEMU agent.

### Cloud-init on Windows

PVE presents cloud-init to Windows guests as an OpenStack config-drive (`citype configdrive2`, the default for any Windows `ostype`), so the generated Cloudbase-Init configuration uses `ConfigDriveService`. Three behaviours differ from a Linux template:

| Setting | Behaviour on a Windows clone |
|---|---|
| `--ciuser` | **No-op.** Cloudbase-Init acts on the account named in its own config file. Fixed at build time by `--ci-username` (default `Administrator`) |
| `--cipassword` | Works — arrives as `admin_pass` in `meta_data.json` and is applied to the managed account. A clone without `--cipassword` keeps the build-time administrator password (printed once during the build). Note `qm cloudinit dump <id> meta` does **not** show it: that subcommand renders the generic config-drive metadata, not the Cloudbase-Init variant PVE actually generates for Windows guests |
| `--sshkeys` | Works — written to `C:\Users\<ci-username>\.ssh\authorized_keys`. Windows Server has no SSH server by default, so the keys sit unused until you install the OpenSSH Server feature |
| `--name` (hostname) | Works, but **only** because `UserDataPlugin` is enabled. PVE's Windows `meta_data.json` carries no `hostname` key; the hostname arrives inside `user_data` as cloud-config. Removing `UserDataPlugin` from `cloudbase-init.conf` silently breaks `qm clone --name` |
| `qm resize` | Works — `ExtendVolumesPlugin` grows `C:`. The generated disk layout deliberately omits a trailing WinRE recovery partition, which would otherwise make `C:` unextendable. Server 2025 Setup appends one regardless of the answer file, so the build disables WinRE and reclaims that partition before sealing (`RECOVERY-RECLAIMED` in the build log); 2019 and 2022 report `RECOVERY-NONE` |

```bash
qm clone 9020 130 --name winsrv01 --full
qm set 130 --ipconfig0 ip=10.0.0.30/24,gw=10.0.0.1 --nameserver 10.0.0.1
qm set 130 --cipassword 'secret' --sshkeys ~/.ssh/id_ed25519.pub
qm start 130
```

### Addons

The core template ships the fixed payloads (virtio, guest agent, SPICE agent, Cloudbase-Init). To bake **additional software** into it — an AV or inventory agent, a portable toolset, an MSI your images "always" carry — point the builder at one or more addon directories:

```bash
pve-build-windows-template --iso dstore01:iso/win2022.iso --storage dstore01 \
    --addons ./samples/addons
```

`--addons DIR` accepts either a single addon (a directory containing an `addon.conf`) or a directory of addon sub-dirs run in sorted order — so the `10-`, `20-`, `30-` name prefixes control sequencing. The flag is repeatable; `--addon` is an alias. In remote mode the addon directories are copied to the node alongside the script. As with `--iso`, **no binary is ever downloaded or bundled**: you supply every installer.

Worked examples live under [`samples/addons/`](samples/addons/): `10-7zip` (silent MSI), `20-sysinternals` (copy files + PATH), and `30-wazuh` (the two-phase agent below).

**Two phases.** An addon can act at build time, at first boot of each clone, or both:

1. **Build time** — the installer named by `type` runs inside the build VM after the core payloads and **before** sysprep, so the software is present in every clone. Progress lands in `C:\pvebuild\state.txt` as `ADDON-<name>-OK` / `-FAIL(rc)`, and each MSI logs to `C:\pvebuild\addon-<name>.log`.
2. **First boot** — if the addon declares `firstboot=`, that script is baked into Cloudbase-Init's LocalScripts and runs **once per clone** (a clone gets a fresh cloud-init instance-id, so LocalScripts execute exactly once). This is where software gets its **per-instance identity** — the reason a template can't simply pre-enrol an agent: every clone must register as *itself*.

**The `addon.conf` contract** (`KEY=VALUE`, `#` comments ignored):

| Key | Applies to | Meaning |
|-----|-----------|---------|
| `type` | all | `msi` \| `exe` \| `copy` \| `script` (required) |
| `file` | msi/exe/script | installer file, relative to the addon dir |
| `args` | msi/exe/script | extra arguments (msi: appended after `/i FILE /qn /norestart`) |
| `dest` | copy | Windows destination path (e.g. `C:\Tools`) |
| `payload` | copy | source sub-dir to copy (default `payload`) |
| `path_add` | copy | `1` appends `dest` to the system PATH |
| `timeout` | msi/exe/script | seconds before the installer is killed (default `600`) |
| `codes` | msi/exe/script | comma-separated success exit codes (default `0,3010`) |
| `required` | all | `1` aborts the build on failure; default `0` (advisory — a failed optional addon only warns) |
| `firstboot` | all | script baked into Cloudbase-Init LocalScripts, run once per clone |

An addon that ships its own virtio drivers and downgrades the set installed earlier is caught and fails the build, the same guard the core payloads use.

**Per-instance identity is your choice.** The `firstboot` hook is source-agnostic. A first-boot script can read its identity/config from:

- **cloud-init user-data** on the PVE cloud-init drive — self-contained and air-gap friendly;
- **PVE metadata** — the hostname (`--name`), instance-id and network PVE injects automatically (enough when an agent only needs a stable name);
- **an external enrolment server** — call the management console for a per-VM token, keeping secrets off the cloud-init drive.

The `30-wazuh` example demonstrates the whole path: the agent MSI is installed at build time with no manager, and `firstboot.ps1` enrols each clone under its own hostname on first boot. A well-behaved first-boot script **no-ops cleanly** when its configuration is absent, so a template cloned without settings still boots to a healthy VM.

**Clone-time package managers.** For packages chosen *per clone* rather than baked into the image, drive a package manager from Cloudbase-Init user-data instead of an addon. [`samples/ci-userdata-chocolatey.yaml`](samples/ci-userdata-chocolatey.yaml) bootstraps Chocolatey and installs a per-VM package list at first boot via `UserDataPlugin`.

**Limitations:**

- Windows Server only — desktop Windows editions are not supported
- UEFI/GPT only; no BIOS/MBR installs
- Domain join at build time is out of scope — it belongs at clone time
- **Cloud-init addressing is only reliable for a single NIC, or for several NICs of the same model.** PVE's Windows config-drive writes the network configuration as Debian ENI with no MAC address (`cloudbase_network_eni()` in `PVE/QemuServer/Cloudinit.pm`), so Cloudbase-Init assigns `ipconfig0`, `ipconfig1`, … in Windows adapter-enumeration order rather than by identity. Two virtio NICs added in order enumerate in the same order and map correctly. Mixed models do not: a clone with `net0` e1000 plus `net1`/`net2` virtio received all three addresses rotated onto the wrong adapters, because Windows enumerates the virtio adapters ahead of the e1000. Give extra NICs their addresses by other means (DHCP, or in-guest configuration). Adding NICs, disks or any other hardware to a clone is otherwise unrestricted — only cloud-init's automatic addressing is affected
- Cloudbase-Init is always installed; there is no `--no-cloudbase-init` escape hatch in this release
- The virtio-win `qxldod` display driver has no INF for Server 2022 or 2025, so `--vga std` is the default. The SPICE agent is installed regardless — the display type is a clone-time decision via `qm set <id> --vga qxl`. The `spice-agent` service is registered `Automatic` but only runs while a SPICE display is attached, so it reads `Stopped` on a `--vga std` clone; that is correct, not a failed install
- The virtio-win ISO must be new enough for the target release; the script refuses to build rather than producing a broken template
- On **Server Core**, Device Manager shows one undriveable `PCI Device` (`8086:293E`, the ICH9 HD Audio controller). PVE's q35 machine definition attaches it to every VM — see the `FIXME: Remove this audio0 device` in `/usr/share/qemu-server/pve-q35-4.0.cfg` — and Server Core ships no audio driver. It is cosmetic, affects any q35 Windows Server Core guest on PVE, and is not something this script adds or can remove

**Dependencies (local mode):** `qm`, `pvesm`, `pvesh`, `genisoimage` (or `mkisofs`), `wiminfo` (wimtools), `guestfish` (libguestfs-tools), `curl`, `python3`.

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
cp pve-import-cloud-images pve-vmnic-fix pve-sdn-healthcheck pve-rolling-upgrade pve-ceph-upgrade pve-build-windows-template /usr/local/sbin/
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
