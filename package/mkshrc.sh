#!/bin/env sh

# ==UserScript==
# @name         mkshrc
# @namespace    https://github.com/user/mkshrc/
# @version      1.1
# @description  Advanced shell environment configuration for Android devices (mksh/sh compatible)
# @author       user
# @match        Android
# ==/UserScript==

###############################################################################
# Utility Functions
###############################################################################

# Check if a command exists in PATH
function _exist() {
  command -v "$1" >/dev/null 2>&1
}

# Resolve the actual binary path, handling aliases
# Example: if "ls" is an alias, this returns the real command target
function _resolve() {
  local binary="$1"
  local resolved="$(command -v "$binary" 2>/dev/null)"

  # If the result is an alias, extract the target
  if echo "$resolved" | grep -q '^alias '; then
    # Extract alias target
    binary="$(echo "$resolved" | grep -o '^alias .*$' | cut -d '=' -f2-)"
    #binary="$(echo "$resolved" | cut -d '=' -f2-)"
  fi

  # Remove surrounding quotes if present
  echo "$binary" | sed "s/^'\(.*\)'$/\1/"
}

###############################################################################
# Environment Setup
###############################################################################

export HOSTNAME="$(getprop ro.boot.serialno)" # Android device serial
export USER="$(id -u -n)"                     # Current username
export LOGNAME="$USER"                        # Ensure LOGNAME matches USER
export TMPDIR='/data/local/tmp'               # Temporary directory
export STORAGE='/storage/self/primary'        # Default shared storage (internal)

###############################################################################
# Aliases and Quality of Life Shortcuts
###############################################################################

# Detect whether the terminal supports color (via ls check)
ls --color=auto "$TMPDIR" >/dev/null 2>&1 && color_prompt=yes

if [ "$color_prompt" = yes ]; then
  # Enable colorized output if supported
  alias ls='ls --color=auto'
  alias grep='grep --color=auto'
  alias fgrep='fgrep --color=auto'
  alias egrep='egrep --color=auto'
  alias logcat='logcat -v color'
  alias diff='diff --color'
fi

# Common shortcuts
alias ll='ls -alF' # long list with file types
alias la='ls -A'   # list all except . and ..
alias l='ls -CF'   # compact list
alias rm='rm -rf'  # recursive remove (dangerous but convenient)

# Networking commands
_exist ip && {
  [ "$color_prompt" = yes ] && alias ip='ip -c'
  alias ipa='ip a' # Show IP addresses
}

# Fallbacks for common tools if not present
_exist ss || alias ss='netstat'
_exist nc || alias nc='netcat'

# Use ps -A if it shows more processes than default ps
[ "$(ps -A | wc -l)" -gt 1 ] && alias ps='ps -A'

# Create a custom colored find command if both find and color support are available
_exist find && [ "$color_prompt" = yes ] && {
  alias cfind="find \"$*\" | sed 's/\\n/ /g' | xargs $(_resolve ls) -d"
}

# Fix mksh vi mode issues when editing multi-line
function _vi() {
  # https://github.com/matan-h/adb-shell/blob/main/startup.sh#L52
  set +o emacs +o vi-tabcomplete
  vi "$@"
  set -o emacs -o vi-tabcomplete
}
alias vi=_vi

# Basic replacement for "man" since Android usually lacks it
function man() {
  local binary="$(_resolve "$1" | cut -d ' ' -f1)"

  # Handle empty or recursive call (man man)
  if [ -z "$binary" ] || [ "$binary" = 'man' ]; then
    echo -e "What manual page do you want?\nFor example, try 'man ls'." >&2
    return 1
  fi

  # Use --help output as a poor-man’s manual
  local manual="$("$binary" --help 2>&1)"
  if [ $? -eq 127 ] || [ -z "$manual" ]; then
    echo "No manual entry for $binary" >&2
    return 16
  fi

  $binary --help
}
export man

# Sudo wrapper (works with root / su / Magisk)
function sudo() {
  [ $# -eq 0 ] && {
    echo 'Usage: sudo <command>' >&2
    return 1
  }

  local binary="$(_resolve "$1")"
  local prompt="$(echo "$@" | sed "s:$1:$binary:g")"

  if [ "$(id -u)" -eq 0 ]; then
    # Already root
    $prompt
  else
    _exist su || {
      echo 'su binary not found' >&2
      return 127
    }

    # Detect su format (standard or Magisk)
    if su --help 2>&1 | grep -q -- '-c'; then
      su -c "$prompt"
    else
      su root "$prompt"
    fi
  fi
}
export sudo

# Frida server management
function frida() {
  # Ensure the frida-server binary is available
  _exist frida-server || {
    echo 'frida-server binary not found in PATH' >&2
    return 1
  }

  # Verify that the current user has root privileges
  [ "$(sudo id -un 2>&1)" = 'root' ] || {
    echo 'Permission denied. Privileged user not available.'
    exit 1
  }

  case "$1" in
  start)
    # Start Frida server if not already running
    frida status >/dev/null 2>&1 && {
      echo 'Frida is already running.' >&2
      return 1
    }
    #sudo setenforce 0 >/dev/null 2>&1 # disable SELinux temporarily
    sudo frida-server -D || {
      echo 'Failed to start Frida.' >&2
      return 1
    }
    ;;
  status)
    # Check if Frida server is running
    local pid="$(pgrep -f frida-server)"
    [ -z "$pid" ] && {
      echo 'Frida is not running.' >&2
      return 1
    }
    echo "Frida is running with PID: $pid"
    ;;
  stop)
    # Stop Frida server and re-enable SELinux
    sudo kill -9 $(pgrep -f frida-server) 2>/dev/null
    sudo setenforce 1 >/dev/null 2>&1
    sleep 1

    frida status >/dev/null 2>&1 && {
      _exist magisk && echo 'Use Magisk to stop Frida.' >&2 || echo 'Frida is still running.' >&2
      return 1
    }
    ;;
  *)
    # Invalid usage
    echo 'Usage: frida {start|status|stop}' >&2
    return 1
    ;;
  esac
}
export frida

###############################################################################
# Persistence Handling (mkshrc overlay before reboot)
###############################################################################

SYSTEM_RC='/system/etc'
VENDOR_RC='/vendor/etc'
DEFAULT_RC="$TMPDIR"

# Detect where to install mkshrc based on privilege
function _detect() {
  if [ "$(sudo id -un 2>&1)" = 'root' ]; then
    [ -f "$SYSTEM_RC/mkshrc" ] && echo "$SYSTEM_RC" && return
    [ -f "$VENDOR_RC/mkshrc" ] && echo "$VENDOR_RC" && return
  fi
  echo "$1"
}

rc_root="$DEFAULT_RC"            # fallback to temp dir
rc_tmpfs="$(_detect "$rc_root")" # check for root locations

#echo "[D] RC root path: $rc_root"
#echo "[D] RC tmpfs path: $rc_tmpfs"

# If persistent mode possible, mount tmpfs over target path
if [ "$rc_root" != "$rc_tmpfs" ]; then
  if [ ! -d "$rc_tmpfs/bin" ]; then
    # Create a temporary backup directory
    local rc_bak="$(mktemp -d)"

    # Copy all existing files from the tmpfs target into the backup directory
    sudo cp -af "$rc_tmpfs"/* "$rc_bak"
    #sudo cp -dprf "$rc_tmpfs"/* "$rc_bak"

    # Mount a tmpfs filesystem over the target directory
    sudo mount -t tmpfs tmpfs "$rc_tmpfs"

    # Restore the backup files into the newly mounted tmpfs
    sudo cp -af "$rc_bak"/* "$rc_tmpfs"
    sudo rm -rf "$rc_bak" # Clean up temporary backup

    # Copy the current script into tmpfs
    sudo ln -sf "$DEFAULT_RC/mkshrc" "$rc_tmpfs/mkshrc"

    # Recursively copy the "bin" folder (containing binaries) into tmpfs
    sudo ln -sf "$rc_root/bin" "$rc_tmpfs/bin"

    # Set ownership of all files in tmpfs to root:root
    sudo chown -R root:root "$rc_tmpfs"

    # Restoring SELinux objects by default
    sudo chcon -R u:object_r:system_file:s0 "$rc_tmpfs"
    sudo chcon u:object_r:cgroup_desc_file:s0 "$rc_tmpfs/cgroups.json" >/dev/null 2>&1
    sudo chcon u:object_r:system_event_log_tags_file:s0 "$rc_tmpfs/event-log-tags" >/dev/null 2>&1
    sudo chcon u:object_r:system_group_file:s0 "$rc_tmpfs/group" >/dev/null 2>&1
    sudo chcon u:object_r:system_passwd_file:s0 "$rc_tmpfs/passwd" >/dev/null 2>&1
    sudo chcon u:object_r:system_linker_config_file:s0 "$rc_tmpfs/ld.config."* >/dev/null 2>&1
    sudo chcon -R u:object_r:system_seccomp_policy_file:s0 "$rc_tmpfs/seccomp_policy/" >/dev/null 2>&1
    sudo chcon u:object_r:system_linker_config_file:s0 "$rc_tmpfs/somxreg.conf" >/dev/null 2>&1
    sudo chcon u:object_r:task_profiles_file:s0 "$rc_tmpfs/task_profiles.json" >/dev/null 2>&1

    # Provide edition support
    sudo chcon -R u:object_r:shell_data_file:s0 "$rc_tmpfs/mkshrc" "$rc_tmpfs/bin"

    rc_root="$rc_tmpfs"
    echo '[I] Script mount permanently until next reboot'
  #else
  #  echo '[D] RC already defined persistently'
  fi
else
  echo '[E] RC in persistent mode unavailable'
  echo '[W] Script sets for current shell context only'
fi

rc_bin="$rc_root/bin"

# Add to PATH if not already there
echo "$PATH" | grep -q "$rc_bin" || export PATH="$PATH:$rc_bin"

# Provide supolicy fallback (used in Magisk contexts)
[ -f "$rc_bin/libsupol.so" ] && alias supolicy="LD_LIBRARY_PATH='$rc_bin' $rc_bin/supolicy"

###############################################################################
# Prompt & Colors
###############################################################################

set +o nohup # disable nohup mode

# Keep PS4 with timestamps
PS4='[$EPOCHREALTIME] '

# Regular colors
BLACK=$'\E[0;30m'
RED=$'\E[0;31m'
GREEN=$'\E[0;32m'
YELLOW=$'\E[0;33m'
BLUE=$'\E[0;34m'
MAGENTA=$'\E[0;35m'
CYAN=$'\E[0;36m'
WHITE=$'\E[0;37m'

# Bright colors
BRIGHT_BLACK=$'\E[1;30m'
BRIGHT_RED=$'\E[1;31m'
BRIGHT_GREEN=$'\E[1;32m'
BRIGHT_YELLOW=$'\E[1;33m'
BRIGHT_BLUE=$'\E[1;34m'
BRIGHT_MAGENTA=$'\E[1;35m'
BRIGHT_CYAN=$'\E[1;36m'
BRIGHT_WHITE=$'\E[1;37m'

# Styles
BOLD=$'\E[1m'
UNDERLINE=$'\E[4m'
REVERSE=$'\E[7m'

# Reset
RESET=$'\E[0m'

# Shell context (SELinux domain)
ctx_shell="$(id -Z 2>/dev/null | awk -F: '{print $3}')"

# Prompt color: red for root, blue for user
if [ "$(id -u)" -eq 0 ]; then
  ctx_color="$RED"
  ctx_type='#'
else
  ctx_color="$BRIGHT_BLUE"
  ctx_type='$'
fi

# Build PS1 with exit code and color if supported
if [ "$color_prompt" = yes ]; then
  PS1='${|
    local e=$?

    (( e )) && REPLY+="${RESET}${RED}${e}${WHITE}|"

    return $e
  }${YELLOW}(${ctx_shell}) ${ctx_color}${USER}@${HOSTNAME}${WHITE}:${BRIGHT_CYAN}${PWD:-?}${WHITE}${ctx_type}${RESET} '
else
  PS1='${|
    local e=$?

    (( e )) && REPLY+="${e}|"

    return $e
  }(${ctx_shell}) ${USER}@${HOSTNAME}:${PWD:-?}${ctx_type} '
fi

# TODO: add persistent history via custom function
# https://github.com/matan-h/adb-shell/blob/main/startup.sh#L73
