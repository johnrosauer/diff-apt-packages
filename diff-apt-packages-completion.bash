# bash completion for diff-apt-packages.sh version @VERSION@
#
# Copyright (C) 2026 John Rosauer <john.rosauer@gmail.com> and Antigravity
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
#

_diff_apt_packages() {
    local cur prev opts mode_opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    
    opts="-m --mode -d --default-file -o --output-dir -w --width -i --installed-manifest -c --no-cache -a --show-added -r --show-removed -k --keep-versions -q --quiet -y --non-interactive -v --version -h --help"
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
