# Addon examples for `pve-build-windows-template`

An **addon** installs extra software into a Windows template at build time and,
optionally, runs a **first-boot init script once per clone** so software that
needs a per-instance identity (an inventory or AV agent enrolling with its own
name/token) configures itself when the VM is instantiated — not baked into the
golden image.

Point the builder at this directory (or a copy of it) with `--addons`:

```
pve-build-windows-template --iso dstore01:iso/win2022.iso \
    --storage ceph-vm --addons ./samples/addons
```

`--addons DIR` accepts either a single addon (a directory containing an
`addon.conf`) or, as here, a directory of addon sub-dirs. Sub-dirs run in
**sorted order**, so the `10-`, `20-`, `30-` name prefixes control sequencing.
The flag is repeatable (`--addon` is an alias).

## The `addon.conf` contract

`addon.conf` is `KEY=VALUE`, one per line; `#` comments and blank lines ignored.

| Key | Applies to | Meaning |
|-----|-----------|---------|
| `type` | all | `msi` \| `exe` \| `copy` \| `script` (required) |
| `file` | msi/exe/script | installer file, relative to the addon dir |
| `args` | msi/exe/script | extra arguments (msi: appended after `/i FILE /qn /norestart`) |
| `dest` | copy | Windows destination path, e.g. `C:\Tools` |
| `payload` | copy | source sub-dir to copy (default `payload`) |
| `path_add` | copy | `1` appends `dest` to the system PATH |
| `timeout` | msi/exe/script | seconds before the installer is killed (default 600) |
| `codes` | msi/exe/script | comma-separated success exit codes (default `0,3010`) |
| `required` | all | `1` makes a failure abort the build (default `0`, advisory) |
| `firstboot` | all | optional script baked into Cloudbase-Init LocalScripts, run once per clone |

## Two phases

1. **Build time** — the installer (`type`) runs inside the build VM after the
   core payloads (virtio, guest agent, Cloudbase-Init) and **before** sysprep,
   so the software is present in every clone. Progress is recorded in
   `C:\pvebuild\state.txt` as `ADDON-<name>-OK` / `-FAIL(rc)` and each MSI logs
   to `C:\pvebuild\addon-<name>.log`.
2. **Clone / first boot** — if the addon declares `firstboot=`, that script is
   copied into Cloudbase-Init's `LocalScripts` directory and runs **once on the
   first boot of each clone** (a clone gets a fresh cloud-init instance-id, so
   LocalScripts execute exactly once). This is where per-instance identity is
   applied.

## Where per-instance identity comes from (your choice)

The first-boot hook is deliberately **source-agnostic**. Common patterns, all
usable from a `firstboot` script:

- **cloud-init user-data** on the PVE cloud-init drive — set `--cicustom` /
  user-data per clone and read it at first boot (self-contained, air-gapped).
- **PVE metadata** — hostname (`--name`), instance-id and network that PVE
  injects automatically; enough when the agent only needs a stable name/ID.
- **External enrollment server** — the script calls the management server
  (AV console, inventory backend) to obtain a per-VM token; keeps secrets off
  the cloud-init drive but needs network reachability at first boot.

A well-behaved `firstboot` script **no-ops cleanly** (logs and exits 0) when its
required values are absent, so a template cloned without configuration still
boots to a healthy VM.

## No binaries are committed

Per the repo's licensing stance, these examples reference freely-available
software but do **not** bundle it. Each example's `README.md` says where to
download the binary and where to drop it. Nothing is fetched automatically.

## The examples here

| Dir | Type | Phase(s) | Demonstrates |
|-----|------|----------|--------------|
| `10-7zip` | msi | build | Automation-friendly silent MSI install |
| `20-sysinternals` | copy | build | "Copy files around" + add to PATH |
| `30-wazuh` | msi + firstboot | build + clone | Install once, enroll per-VM with its own identity |

See also `../ci-userdata-chocolatey.yaml` for the **clone-time package-manager**
route (Chocolatey via Cloudbase-Init user-data) — per-VM packages that are
*not* baked into the template.
