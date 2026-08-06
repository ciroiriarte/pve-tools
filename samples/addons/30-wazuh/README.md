# 30-wazuh — install in the template, enrol per-VM on first boot

This is the two-phase example that motivates the whole facility: software that
is **installed once in the template** but must be **initialized per instance**
with a unique identity. The open-source [Wazuh](https://wazuh.com/) agent is a
realistic stand-in for the AV / inventory agents that "always should be
installed" but must register as *this* VM, not as the template.

## The two phases

1. **Build time** — `addon.conf` (`type=msi`) installs the agent MSI into the
   template. No `WAZUH_MANAGER` is passed, so nothing enrols with the template's
   throwaway identity.
2. **First boot of each clone** — `firstboot.ps1` was baked into Cloudbase-Init's
   LocalScripts. It runs once per clone (fresh instance-id), sets the agent name
   to the clone's hostname, points it at your manager, registers, and starts the
   service.

## Use it

1. Download the Windows agent MSI from <https://packages.wazuh.com/> and drop it
   here; set `file=` in `addon.conf` to match.
2. Build with `--addons /path/to/samples/addons`.
3. Give each clone its Wazuh settings. The example `firstboot.ps1` reads a
   `KEY=VALUE` file at `C:\ProgramData\pve-addons\wazuh.conf`:

   ```
   manager=10.0.0.10
   group=windows-servers
   ```

   Have your per-clone cloud-init **user-data** write that file (or adapt
   `firstboot.ps1` to read the manager from PVE metadata or an enrolment
   server — see the comments in the script). With no manager configured, the
   script no-ops and the VM boots normally.

## Identity source is your choice

`firstboot.ps1` is deliberately source-agnostic and documents three patterns in
its header:

- **cloud-init user-data** — self-contained, air-gapped (the pattern above).
- **PVE metadata** — the agent *name* is always `$env:COMPUTERNAME`, i.e. the
  hostname PVE assigned the clone.
- **external enrolment server** — point `manager` at your console and let the
  `agent-auth` handshake register the VM.

## Verifying

On a clone, check `C:\ProgramData\pve-addons\wazuh-firstboot.log` and confirm the
agent shows up on the manager under the clone's hostname. A second reboot does
not re-enrol (guarded by `wazuh-firstboot.done`).
