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

# Function rc to display the return code
function rc {
    [[ $? -eq 0 ]] && echo -e "\e[01;34m" || echo -e "\e[01;31m"
}

# Function to display the current Git branch
function parse_git_branch {
    git branch 2>/dev/null | grep '\*' | sed 's/* //'
}

# Prompt configuration
function __setprompt {
    local LAST_COMMAND=$? # Capture the return code of the last command

    # Colors
    local LIGHTGRAY="\033[0;37m"
    local DARKGRAY="\033[1;30m"
    local RED="\033[0;31m"
    local MAGENTA="\033[0;35m"
    local CYAN="\033[0;36m"
    local BLUE="\033[0;34m"
    local BROWN="\033[0;33m"
    local GREEN="\033[0;32m"
    local NOCOLOR="\033[0m"
    local WHITE="\033[0;37m"

    # Date and time
    PS1="\
\[${WHITE}\](\[${MAGENTA}\]\$(date +%A) \[${MAGENTA}\]\$(date +%-d) \[${MAGENTA}\]\$(date +%b)${WHITE})\
\[${WHITE}\](${BLUE}\$(date +'%H:%M:%S')\[${WHITE}\])"

    # SSH information
    local SSH_IP=$(echo $SSH_CLIENT | awk '{ print $1 }')
    local SSH2_IP=$(echo $SSH2_CLIENT | awk '{ print $1 }')
    if [ -n "$SSH_IP" ] || [ -n "$SSH2_IP" ]; then
        PS1+="(\[${RED}\]\u@\h\[${WHITE}\]:\[${BROWN}\]\w\[${WHITE}\])"
    else
        PS1+="(\[${RED}\]\u\[${WHITE}\]:\[${BROWN}\]\w\[${WHITE}\])"
    fi

    # Add the current Git branch name only if inside a Git repository
    if git rev-parse --is-inside-work-tree &>/dev/null; then
        PS1+="\[${WHITE}\](\[${CYAN}\]\$(parse_git_branch | sed 's/^ //g')\[${WHITE}\])"
    fi

    # Total size of files in the current directory
    local total_size=$(ls -lah | awk '/^total/ {print $2}')

    # Number of directories and files
    local num_dirs=$(find . -maxdepth 1 -type d | wc -l)
    local num_files=$(find . -maxdepth 1 -type f | wc -l)

    # Adjust the directory count to exclude the current directory
    num_dirs=$((num_dirs - 1))

    PS1+="(\[${GREEN}\]${total_size}:\[${GREEN}\]${num_dirs}D:\[${GREEN}\]${num_files}F\[${WHITE}\])"

    # New line
    PS1+="\n"

    # Prompt for normal user or root
    if [[ $EUID -ne 0 ]]; then
        PS1+="\[${GREEN}\]>\[${NOCOLOR}\] " # Normal user
    else
        PS1+="\[${RED}\]>\[${NOCOLOR}\] " # Root user
    fi

    # PS2 for continuing a command
    PS2="\[${WHITE}\]>\[${NOCOLOR}\] "

    # PS3 for script choices
    PS3='Please enter a number from above list: '

    # PS4 for debugging
    PS4='\[${WHITE}\]+\[${NOCOLOR}\] '
}

# Define the prompt command
PROMPT_COMMAND='__setprompt'

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
