# bash completion for pve-tools
# Source this file or copy it to /etc/bash_completion.d/

# --- pve-vmnic-fix ------------------------------------------------------------

_pve_vmnic_fix() {
    local cur prev opts
    _init_completion || return

    opts="-a --all -n --dry-run -h --help -v --version"

    case "$prev" in
        -a|--all|-n|--dry-run|-h|--help|-v|--version)
            COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
            return
            ;;
    esac

    if [[ "$cur" == -* ]]; then
        COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
    fi
}

complete -F _pve_vmnic_fix pve-vmnic-fix

# --- pve-import-cloud-images --------------------------------------------------

_pve_import_cloud_images() {
    local cur prev opts
    _init_completion || return

    opts="-i --interactive -b --batch -l --list
          -m --mode -s --storage -B --bridge -f --format
          -S --disk-size -I --start-id -d --distro
          --force --no-customize --arch
          --api-host --api-node --api-token --api-import-storage
          -n --dry-run -h --help -v --version"

    case "$prev" in
        -m|--mode)
            COMPREPLY=( $(compgen -W "local api" -- "$cur") )
            return
            ;;
        -f|--format)
            COMPREPLY=( $(compgen -W "raw qcow2" -- "$cur") )
            return
            ;;
        -d|--distro)
            COMPREPLY=( $(compgen -W "debian ubuntu rocky opensuse oracle freebsd" -- "$cur") )
            return
            ;;
        --arch)
            COMPREPLY=( $(compgen -W "x86_64 aarch64" -- "$cur") )
            return
            ;;
        -s|--storage|-B|--bridge|--api-import-storage)
            # No useful default completions; let the user type
            return
            ;;
        -S|--disk-size|-I|--start-id|--api-host|--api-node|--api-token)
            # Expects a value; no completions
            return
            ;;
    esac

    if [[ "$cur" == -* ]]; then
        COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
    fi
}

complete -F _pve_import_cloud_images pve-import-cloud-images

# --- pve-create-tshoot-image --------------------------------------------------

_pve_create_tshoot_image() {
    local cur prev opts
    _init_completion || return

    opts="-t --template -c --csv -s --storage -o --output
          -S --server --rescue-only --rear-timeout
          --bond-mode --vlan-id --netmask --gateway --dns --proxy
          --vm-bridge --vm-vlan --vm-ip --vm-gateway --vm-dns --vm-proxy
          --dry-run -h --help -v --version"

    case "$prev" in
        -c|--csv)
            _filedir csv
            return
            ;;
        -o|--output)
            _filedir -d
            return
            ;;
        --bond-mode)
            COMPREPLY=( $(compgen -W "802.3ad balance-rr balance-xor broadcast balance-tlb balance-alb active-backup" -- "$cur") )
            return
            ;;
        -t|--template|-s|--storage|-S|--server|--rear-timeout)
            # Expects a value; no completions
            return
            ;;
        --vlan-id|--netmask|--gateway|--dns|--proxy)
            return
            ;;
        --vm-bridge|--vm-vlan|--vm-ip|--vm-gateway|--vm-dns|--vm-proxy)
            return
            ;;
    esac

    if [[ "$cur" == -* ]]; then
        COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
    fi
}

complete -F _pve_create_tshoot_image pve-create-tshoot-image

# --- pve-sdn-healthcheck ------------------------------------------------------

# Canonical check names (keep in sync with `pve-sdn-healthcheck --list-checks`).
_PVE_SDN_CHECKS="ip_forward frr_daemon iface_link iface_errors iface_flap \
optics_dom bond_lacp mtu_local bgp_evpn bgp_external vtep_reach ceph_net \
evpn_vnis evpn_routes irb_gw l3vni_fdb rib_fib vrf_reach vmnic_plumbing"

_pve_sdn_healthcheck() {
    local cur prev opts
    _init_completion || return

    opts="--node --only --check --explain --drop-window --parallel -a --all --json --no-color
          --list-checks --fix --apply -y --yes -h --help -v --version"

    case "$prev" in
        --only)
            COMPREPLY=( $(compgen -W "underlay overlay" -- "$cur") )
            return
            ;;
        --check|--explain)
            COMPREPLY=( $(compgen -W "$_PVE_SDN_CHECKS" -- "$cur") )
            return
            ;;
        --fix)
            # --fix takes an optional check name (auto-fixable subset)
            COMPREPLY=( $(compgen -W "ip_forward vmnic_plumbing frr_daemon" -- "$cur") )
            return
            ;;
        --node)
            # Host/IP list; no useful default completions
            return
            ;;
    esac

    if [[ "$cur" == -* ]]; then
        COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
    fi
}

complete -F _pve_sdn_healthcheck pve-sdn-healthcheck

# --- pve-rolling-upgrade ------------------------------------------------------

_pve_rolling_upgrade() {
    local cur prev opts
    _init_completion || return

    opts="-j --jump -s --stable -t --target --nic-pin --target-kernel
          -n --dry-run --no-color -h --help -v --version"

    case "$prev" in
        --nic-pin)
            COMPREPLY=( $(compgen -W "keep pmx" -- "$cur") )
            return
            ;;
        -j|--jump|-s|--stable|-t|--target|--target-kernel)
            # Host/IP or value; no useful default completions
            return
            ;;
    esac

    if [[ "$cur" == -* ]]; then
        COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
    fi
}

complete -F _pve_rolling_upgrade pve-rolling-upgrade

# --- pve-ceph-upgrade ---------------------------------------------------------

_pve_ceph_upgrade() {
    local cur prev opts
    _init_completion || return

    opts="--to --from -j --jump -s --stable -y --yes
          -n --dry-run --no-color -h --help -v --version"

    case "$prev" in
        --to|--from)
            COMPREPLY=( $(compgen -W "quincy reef squid tentacle" -- "$cur") )
            return
            ;;
        -j|--jump|-s|--stable)
            # Host/IP; no useful default completions
            return
            ;;
    esac

    if [[ "$cur" == -* ]]; then
        COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
    fi
}

complete -F _pve_ceph_upgrade pve-ceph-upgrade

# --- pve-build-windows-template -----------------------------------------------

_pve_build_windows_template() {
    local cur prev opts
    _init_completion || return

    opts="-i --iso --eval -R --release --virtio-iso --cloudbase-msi --spice-msi
          --addons --addon
          -e --edition -k --sku -I --start-id --force
          -s --storage --iso-storage -B --bridge --vlan --build-bridge
          -D --disk-size -c --cpu-type --cores --memory
          --build-cores --build-memory --vga --no-tpm --no-secureboot
          --locale --input-locale --timezone --kms-host --no-rdp
          --admin-password --admin-password-file --ci-username
          --product-key --product-key-file --kms
          --cache-dir --refresh-cache --keep-answer-iso --keep-on-failure
          --install-timeout --payload-timeout --sysprep-timeout
          -m --mode -S --server --show-answer-file
          -n --dry-run -h --help -v --version"

    case "$prev" in
        -e|--edition)
            COMPREPLY=( $(compgen -W "core desktop both" -- "$cur") ); return ;;
        -k|--sku)
            COMPREPLY=( $(compgen -W "standard datacenter" -- "$cur") ); return ;;
        --eval|-R|--release)
            COMPREPLY=( $(compgen -W "2019 2022 2025" -- "$cur") ); return ;;
        -m|--mode)
            COMPREPLY=( $(compgen -W "local remote" -- "$cur") ); return ;;
        --vga)
            COMPREPLY=( $(compgen -W "std qxl virtio" -- "$cur") ); return ;;
        -i|--iso|--virtio-iso)
            _filedir iso; return ;;
        --cloudbase-msi)
            _filedir msi; return ;;
        --spice-msi)
            _filedir msi; return ;;
        --admin-password-file|--product-key-file)
            _filedir; return ;;
        --cache-dir|--addons|--addon)
            _filedir -d; return ;;
        -s|--storage|--iso-storage|-B|--bridge|--vlan|--build-bridge|-I|--start-id)
            # Expects a value; no useful default completions
            return ;;
        -D|--disk-size|-c|--cpu-type|--cores|--memory|--build-cores|--build-memory)
            return ;;
        --locale|--input-locale|--timezone|--admin-password|--ci-username)
            return ;;
        --product-key|--kms-host|-S|--server)
            return ;;
        --install-timeout|--payload-timeout|--sysprep-timeout)
            return ;;
    esac

    if [[ "$cur" == -* ]]; then
        COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
    fi
}

complete -F _pve_build_windows_template pve-build-windows-template
