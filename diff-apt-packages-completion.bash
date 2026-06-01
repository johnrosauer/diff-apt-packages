# bash completion for diff-apt-packages.sh version @VERSION@

_diff_apt_packages() {
    local cur prev opts mode_opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    
    opts="-m --mode -d --default-file -o --output-dir -w --width -a --show-added -r --show-removed -k --keep-versions -q --quiet -y --non-interactive -v --version -h --help"
    mode_opts="desktop server wsl cloud auto"
    
    case "$prev" in
        -m|--mode)
            COMPREPLY=( $(compgen -W "${mode_opts}" -- "$cur") )
            return 0
            ;;
        -d|--default-file)
            # Complete files
            _filedir
            return 0
            ;;
        -o|--output-dir)
            # Complete directories only
            _filedir -d
            return 0
            ;;
        -w|--width)
            # Expose no completion as it expects an integer width
            return 0
            ;;
    esac
    
    if [[ "$cur" == -* ]]; then
        COMPREPLY=( $(compgen -W "${opts}" -- "$cur") )
        return 0
    fi
}

complete -F _diff_apt_packages diff-apt-packages.sh diff-apt-packages
