# Wazuh agent per-instance enrolment — runs ONCE on each clone's first boot.
#
# pve-build-windows-template baked this script into Cloudbase-Init's
# LocalScripts at build time. A clone gets a fresh cloud-init instance-id, so
# Cloudbase-Init runs LocalScripts exactly once per clone -- the right place to
# apply a per-VM identity to software that was installed into the template.
#
# IDENTITY SOURCE IS YOUR CHOICE. This example resolves the Wazuh manager from,
# in order:
#   1. cloud-init user-data      -> a file the operator's user-data writes to
#                                   C:\ProgramData\pve-addons\wazuh.conf
#   2. PVE metadata              -> the agent NAME is always the hostname PVE
#                                   assigned this clone ($env:COMPUTERNAME)
#   3. external enrolment server -> point WAZUH_MANAGER at your console; the
#                                   agent-auth handshake below registers the VM
# If no manager is configured, the script logs and exits 0 -- a template cloned
# without Wazuh settings still boots to a healthy VM.

$ErrorActionPreference = 'Continue'

$StateDir = 'C:\ProgramData\pve-addons'
$Log      = Join-Path $StateDir 'wazuh-firstboot.log'
$Done     = Join-Path $StateDir 'wazuh-firstboot.done'
New-Item -ItemType Directory -Force -Path $StateDir | Out-Null

function Log([string]$m) { Add-Content -LiteralPath $Log -Value ("[{0}] {1}" -f (Get-Date -Format s), $m) }

# Belt-and-braces idempotency: Cloudbase-Init already runs LocalScripts once per
# instance-id, but a manual re-run should not re-enrol.
if (Test-Path -LiteralPath $Done) { Log 'already enrolled; nothing to do'; return }

Log 'first-boot enrolment starting'

# --- Resolve configuration (source-agnostic) --------------------------------
$manager = ''
$group   = ''

# Source 1: a KEY=VALUE file the operator's cloud-init user-data dropped.
$confFile = Join-Path $StateDir 'wazuh.conf'
if (Test-Path -LiteralPath $confFile) {
    foreach ($ln in Get-Content -LiteralPath $confFile) {
        $ln = $ln.TrimEnd("`r")
        if ($ln -match '^\s*#') { continue }
        $eq = $ln.IndexOf('=')
        if ($eq -lt 1) { continue }
        $k = $ln.Substring(0, $eq).Trim(); $v = $ln.Substring($eq + 1).Trim()
        if ($k -eq 'manager') { $manager = $v }
        if ($k -eq 'group')   { $group   = $v }
    }
}

# Source 3 alternative: an environment variable / registry value you set from
# user-data. Uncomment to prefer it.
# if (-not $manager) { $manager = [Environment]::GetEnvironmentVariable('WAZUH_MANAGER','Machine') }

if (-not $manager) {
    Log 'no Wazuh manager configured (no C:\ProgramData\pve-addons\wazuh.conf) -- skipping'
    return
}

# Source 2: the per-VM identity. PVE/Cloudbase-Init set the hostname; use it as
# the unique agent name so the manager sees this clone as itself.
$agentName = $env:COMPUTERNAME
Log ("manager={0} group={1} agentName={2}" -f $manager, $group, $agentName)

# --- Enrol ------------------------------------------------------------------
$agentDir = Join-Path ${env:ProgramFiles(x86)} 'ossec-agent'
if (-not (Test-Path -LiteralPath $agentDir)) {
    $agentDir = Join-Path $env:ProgramFiles 'ossec-agent'
}
$ossecConf = Join-Path $agentDir 'ossec.conf'
$agentAuth = Join-Path $agentDir 'agent-auth.exe'

if (-not (Test-Path -LiteralPath $ossecConf)) {
    Log "ossec.conf not found under $agentDir -- is the agent installed?"
    return
}

try {
    Stop-Service -Name Wazuh -ErrorAction SilentlyContinue
    Stop-Service -Name WazuhSvc -ErrorAction SilentlyContinue

    # Point the agent at the manager (replace the <address> in the <client> block).
    $xml = Get-Content -LiteralPath $ossecConf -Raw
    $xml = [regex]::Replace($xml, '<address>.*?</address>', "<address>$manager</address>")
    Set-Content -LiteralPath $ossecConf -Value $xml -Encoding ASCII

    # Register with a per-VM name (and optional group) via the auth handshake.
    if (Test-Path -LiteralPath $agentAuth) {
        $argv = @('-m', $manager, '-A', $agentName)
        if ($group) { $argv += @('-G', $group) }
        # agent-auth writes its progress to stderr; flatten to plain text so
        # the log holds the messages, not PowerShell ErrorRecord objects.
        $authOut = (& $agentAuth @argv 2>&1 | Out-String)
        foreach ($line in ($authOut -split "`r?`n")) { if ($line.Trim()) { Log "agent-auth: $line" } }
    } else {
        Log 'agent-auth.exe missing; relying on manager-side enrolment'
    }

    $svc = if (Get-Service -Name WazuhSvc -ErrorAction SilentlyContinue) { 'WazuhSvc' } else { 'Wazuh' }
    Set-Service -Name $svc -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service -Name $svc -ErrorAction SilentlyContinue

    Set-Content -LiteralPath $Done -Value $agentName -Encoding ASCII
    Log 'enrolment complete'
} catch {
    Log ("enrolment error: " + $_.Exception.Message)
}
