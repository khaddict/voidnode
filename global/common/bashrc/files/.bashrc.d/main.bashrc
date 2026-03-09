# History settings
HISTCONTROL=ignoredups:ignorespace
shopt -s histappend
export HISTTIMEFORMAT="%Y/%m/%d %T "
export HISTSIZE=5000
export HISTFILESIZE=5000

# Check window size after each command
shopt -s checkwinsize

# Handle lesspipe if installed
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# Define debian_chroot if applicable
if [ -z "$debian_chroot" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

# Parse python virtual env
function parse_python_venv {
    if [[ -n "$VIRTUAL_ENV" ]]; then
        basename "$VIRTUAL_ENV"
    fi
}

# Parse Kubernetes context
function parse_k8s_context {
    command -v kubectl >/dev/null 2>&1 || return

    local ctx ns
    ctx=$(kubectl config current-context 2>/dev/null) || return
    ns=$(kubectl config view --minify --output 'jsonpath={..namespace}' 2>/dev/null)

    [[ -z "$ns" ]] && ns="default"

    echo "${ctx}:${ns}"
}

# Parse Git branch
function parse_git_branch {
    git rev-parse --is-inside-work-tree &>/dev/null || return
    git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null
}

# Check if Git repo is dirty
function git_is_dirty {
    git rev-parse --is-inside-work-tree &>/dev/null || return 1

    if ! git diff --quiet 2>/dev/null; then
        return 0
    fi

    if ! git diff --cached --quiet 2>/dev/null; then
        return 0
    fi

    if [[ -n "$(git ls-files --others --exclude-standard 2>/dev/null)" ]]; then
        return 0
    fi

    return 1
}

# Start timer before each command
function __prompt_timer_start {
    [[ -n "${__IN_PROMPT_COMMAND:-}" ]] && return

    case "$BASH_COMMAND" in
        __prompt_command|__prompt_command\ *|__setprompt|__setprompt\ *)
            return
            ;;
    esac

    if [[ -n "${EPOCHREALTIME:-}" ]]; then
        __CMD_START_TIME="$EPOCHREALTIME"
    else
        __CMD_START_TIME=""
    fi
}

# Prompt builder
function __setprompt {
    local LAST_COMMAND="${1:-$?}"

    # Colors
    local RED="\033[0;31m"
    local MAGENTA="\033[0;35m"
    local CYAN="\033[0;36m"
    local GREEN="\033[0;32m"
    local WHITE="\033[1;37m"
    local GRAY="\033[0;90m"
    local YELLOW="\033[1;33m"
    local NOCOLOR="\033[0m"

    PS1=""

    # Date + Time combined
    PS1+="\[${WHITE}\][\[${GRAY}\]\$(date +%a) \$(date +%-d) \$(date +%b) - \$(date +'%H:%M:%S')\[${WHITE}\]]\[${NOCOLOR}\] "

    # User / host / path
    PS1+="\[${WHITE}\][\[${RED}\]\u@\h\[${WHITE}\]:\[${YELLOW}\]\w\[${WHITE}\]]\[${NOCOLOR}\]"

    # Python virtualenv
    local py_venv
    py_venv="$(parse_python_venv)"
    if [[ -n "$py_venv" ]]; then
        PS1+=" \[${WHITE}\][\[${GREEN}\]py:${py_venv}\[${WHITE}\]]\[${NOCOLOR}\]"
    fi

    # Git info
    local git_branch
    git_branch="$(parse_git_branch)"
    if [[ -n "$git_branch" ]]; then
        if git_is_dirty; then
            PS1+=" \[${WHITE}\][\[${CYAN}\]git:${git_branch} \[${RED}\]✗\[${WHITE}\]]\[${NOCOLOR}\]"
        else
            PS1+=" \[${WHITE}\][\[${CYAN}\]git:${git_branch} \[${GREEN}\]✓\[${WHITE}\]]\[${NOCOLOR}\]"
        fi
    fi

    # Kubernetes context
    local k8s_info
    k8s_info="$(parse_k8s_context)"
    if [[ -n "$k8s_info" ]]; then
        PS1+=" \[${WHITE}\][\[${MAGENTA}\]k8s:${k8s_info}\[${WHITE}\]]\[${NOCOLOR}\]"
    fi

    # Last command exit code (only if non-zero)
    if [[ "$LAST_COMMAND" -ne 0 ]]; then
        PS1+=" \[${WHITE}\][\[${RED}\]✗ ${LAST_COMMAND}\[${WHITE}\]]\[${NOCOLOR}\]"
    fi

    # Last command duration (only if >1s)
    if [[ -n "${__LAST_CMD_DURATION:-}" ]]; then
        if awk "BEGIN { exit !(${__LAST_CMD_DURATION} > 1.0) }"; then
            PS1+=" \[${WHITE}\][\[${GRAY}\]${__LAST_CMD_DURATION}s\[${WHITE}\]]\[${NOCOLOR}\]"
        fi
    fi

    PS1+="\n"

    # Prompt char
    PS1+="\[${RED}\]>\[${NOCOLOR}\] "

    PS2="\[${WHITE}\]>\[${NOCOLOR}\] "
    PS3='Please enter a number from above list: '
    PS4='\[${WHITE}\]+\[${NOCOLOR}\] '
}

# Wrapper to compute duration
function __prompt_command {
    local last_exit=$?

    __IN_PROMPT_COMMAND=1

    if [[ -n "${__CMD_START_TIME:-}" && -n "${EPOCHREALTIME:-}" ]]; then
        __LAST_CMD_DURATION="$(awk -v start="$__CMD_START_TIME" -v end="$EPOCHREALTIME" 'BEGIN { printf "%.1f", (end - start) }')"
    else
        __LAST_CMD_DURATION=""
    fi

    __setprompt "$last_exit"

    unset __IN_PROMPT_COMMAND
}

# Enable timer
trap '__prompt_timer_start' DEBUG

PROMPT_COMMAND='__prompt_command'

# Configure dircolors and alias for ls
if [ -x /usr/bin/dircolors ]; then
    if [ -r ~/.dircolors ]; then
        eval "$(dircolors -b ~/.dircolors)"
    else
        eval "$(dircolors -b)"
    fi
    alias ls='ls --color=auto'
fi

export REQUESTS_CA_BUNDLE="/etc/ssl/certs/ca-certificates.crt"
