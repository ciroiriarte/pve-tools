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
