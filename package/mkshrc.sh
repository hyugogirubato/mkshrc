#!/system/bin/sh

# ==UserScript==
# @name         mkshrc
# @namespace    https://github.com/user/mkshrc/
# @version      2.1
# @description  Advanced shell environment configuration for Android devices (mksh/sh compatible)
# @author       user
# @match        Android
# ==/UserScript==

###############################################################################
### Utility Functions
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

# Disable a package for user 0 (hide app without removing APK)
function _disable() {
  pm disable-user --user 0 "$1" >/dev/null 2>&1
  #pm uninstall -k --user 0 "$1" >/dev/null 2>&1 # stronger, reversible
}

# Enable a previously disabled or uninstalled package for user 0
# Restores the app using the existing system APK
function _enable() {
  pm enable --user 0 "$1" >/dev/null 2>&1
  #pm install-existing --user 0 "$1" >/dev/null 2>&1 # restore uninstalled
}

###############################################################################
### Environment Setup
###############################################################################

export HOSTNAME="$(getprop ro.boot.serialno)" # Android device serial
[ -z "$HOSTNAME" ] && export HOSTNAME="$(hostname -s)"
export USER="$(id -u -n)"              # Current username
export LOGNAME="$USER"                 # Ensure LOGNAME matches USER
export TMPDIR='/data/local/tmp'        # Temporary directory
export STORAGE='/storage/self/primary' # Default shared storage (internal)
export HOME='/'                        # Default home directory for shell user

###############################################################################
### Aliases and Quality of Life Shortcuts
###############################################################################

# Detect whether the terminal supports color (via ls check)
ls --color=auto '/system' 2>&1 | grep -q -- '--color' || color_prompt=yes

if [ "$color_prompt" = yes ]; then
  # Enable colorized output if supported
  alias ls='ls --color=auto'
  alias grep='grep --color=auto'
  alias fgrep='fgrep --color=auto'
  alias egrep='egrep --color=auto'
  alias logcat='logcat -v color'
  alias diff='diff --color'

  # Networking commands
  _exist ip && alias ip='ip -c'
fi

# Common shortcuts
alias ll="$(_resolve ls) -alF"     # long list with file types
alias la="$(_resolve ls) -A"       # list all except . and ..
alias l="$(_resolve ls) -CF"       # compact list
alias rm='rm -rf'                  # recursive remove (dangerous but convenient)
alias reset='stty sane < /dev/tty' # restore terminal to default state

# Use ps -A if it shows more processes than default ps
[ "$(ps -A | wc -l)" -gt 1 ] && alias ps='ps -A'

# Provide a convenient poweroff command if not available
_exist poweroff || alias poweroff='reboot -p'

# Sudo wrapper (works with root / su / Magisk)
function sudo() {
  [ $# -eq 0 ] && {
    echo 'Usage: sudo <command>' >&2
    return 1
  }

  # Resolve binary path and rebuild command
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
    local su_pty="$(_resolve su) root"
    if su ---help 2>&1 | grep -q -- '-c'; then
      su_pty="$(_resolve su) -c"
    fi

    # Ensures aliases and multi-word commands are interpreted safely
    $su_pty echo root 2>&1 | grep -q '^root$'
    local quoted=$?

    # Reset PTY to avoid issues with old su / Magisk shells
    reset

    # https://stackoverflow.com/questions/27274339/how-to-use-su-command-over-adb-shell/
    # Quote the command only if needed to preserve spaces or flags
    if [ $quoted -eq 0 ]; then
      $su_pty $prompt
    else
      $su_pty "$prompt"
    fi
  fi
}
export sudo

# Pull files into TMPDIR with proper permissions
function pull() {
  local src_path="$1"
  local tmp_path="$TMPDIR/$(basename "$src_path")"
  local prefix=''

  # Decide whether to use sudo (only if current user is NOT root)
  [ "$(sudo id -un 2>&1)" = 'root' ] && prefix='sudo'

  # Copy file into TMPDIR (suppressing output). Fail fast if copy fails.
  $prefix cp -af "$src_path" "$tmp_path" >/dev/null 2>&1 || {
    echo "Failed to copy $src_path" >&2
    return 1
  }

  # Change ownership to 'shell:shell' so that the adb shell user can access it.
  # -R ensures it works for directories too.
  $prefix chown -R shell:shell "$tmp_path" >/dev/null 2>&1 || {
    echo "Failed to chown $tmp_path" >&2
  }

  # Set SELinux context to match shell data files, again recursive for directories.
  $prefix chcon -R u:object_r:shell_data_file:s0 "$tmp_path" >/dev/null 2>&1 || {
    echo "Failed to set SELinux context on $tmp_path" >&2
  }

  echo "Pulled: $tmp_path"
}
export pull

# System restart (soft reboot / zygote restart)
function restart() {
  # Magisk & other root managers rely on overlayfs or tmpfs mounts that insert or hide su binaries and management files at boot.
  # When you do a soft reboot (zygote / framework restart, not full kernel reboot):
  # - The system services restart.
  # - But Magisk’s init-time mount overlays don’t get re-applied, because init didn’t rerun.
  # Result:
  # - /sbin/su, /system/xbin/su, etc. may not be mounted anymore.
  # - which su won’t find anything in $PATH.

  # Verify that the current user has root privileges
  [ "$(sudo id -un 2>&1)" = 'root' ] || {
    echo 'Permission denied. Privileged user not available.' >&2
    return 1
  }

  # Soft reboot via init: stop and restart the Android framework.
  # This does not reboot the kernel, only restarts system services.
  # Reference: https://source.android.com/docs/core/runtime/soft-restart

  # Effect: Kills all Android framework services and restarts them.
  # Pros: Works on older Android (pre-Android 8 especially), very thorough.
  # Cons:
  # - Slow (almost like a full reboot).
  # - On newer Android (10+), init often blocks this, or services don’t come back cleanly.
  # - Risk of bootloop if start doesn’t fully reinitialize.
  # Not very stable on modern Android.
  #sudo stop
  #sudo start

  # Effect: Signals init to restart the zygote service (which spawns all apps and system_server).
  # Pros:
  # - Officially supported mechanism.
  # - Fast, cleaner than killing processes.
  # - Works on Android 5 → Android latest.
  # Cons: Some devices split into zygote / zygote_secondary, so you may need both.
  # Most stable & recommended across versions.
  sudo setprop ctl.restart zygote

  # Effect: Hard-kills zygote, Android restarts it automatically.
  # Pros: Works even if setprop isn’t available or blocked.
  # Cons:
  # - Dirty (no graceful shutdown).
  # - Can cause crashes, logs filled with errors.
  # - On some devices, may trigger watchdog → full reboot.
  # Works, but hacky and less reliable.
  #sudo kill -9 $(pidof zygote)

  # Effect: Kills system_server; zygote will restart it.
  # Pros: Faster than full zygote restart.
  # Cons:
  # - Leaves zygote alive (not a clean reset).
  # - Often unstable afterward (services missing, ANRs).
  # - Some Android versions will panic → reboot.
  # Least stable.
  #sudo kill -9 $(pidof system_server)
}
export restart

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

# Frida server management
function frida() {
  # Ensure frida-server binary is available
  _exist frida-server || {
    echo 'frida-server binary not found in PATH' >&2
    return 1
  }

  # For start/stop commands, check for root privileges
  if echo "$1" | grep -Eq '^(-s|-k|--start|--stop|start|stop)$' && [ "$(sudo id -un 2>&1)" != 'root' ]; then
    echo 'Permission denied. Privileged user not available.' >&2
    return 1
  fi

  # Handle commands/options
  # https://github.com/ThatNotEasy/mkshrc/blob/main/package/mkshrc.sh#L313
  case "$1" in
  -h | --help | help)
    # Display a concise help page
    cat <<EOF
usage: frida [OPTIONS]

Manage frida-server on Android devices.

options:
  -s, --start      Start frida-server (requires root)
  -k, --stop       Stop frida-server (requires root)
  -S, --status     Show frida-server status
  -v, --version    Show frida-server binary version
  -h, --help       Show this help page

Notes:
  Root access is required for start/stop operations.
  SELinux is temporarily disabled when starting the server.
  Magisk users may manage frida-server via Magisk modules.
EOF
    ;;
  -v | --version | version)
    # Show the version of frida-server
    frida-server --version
    ;;
  -S | --status | status)
    # Check if frida-server is currently running
    local pid="$(pgrep -f frida-server)"
    [ -z "$pid" ] && {
      echo 'Stopped' >&2
      return 1
    }
    echo "Running ($pid)"
    ;;
  -s | --start | start)
    # Start Frida server if not already running
    frida status >/dev/null 2>&1 && {
      echo 'Already running' >&2
      return 1
    }

    # Temporarily disable SELinux to allow frida-server startup
    sudo setenforce 0 >/dev/null 2>&1

    # Start frida-server in daemon mode
    sudo frida-server -D || {
      echo 'Start failed' >&2
      return 1
    }
    echo 'Started'
    ;;
  -k | --stop | stop)
    # Stop frida-server
    sudo kill -9 $(pgrep -f frida-server) 2>/dev/null
    sleep 1

    # Check if frida-server is still running
    frida status >/dev/null 2>&1 && {
      _exist magisk && echo 'Use Magisk to stop' >&2 || echo 'Still running' >&2
      return 1
    }

    # Optional: re-enable SELinux (commented out for safety)
    # sudo setenforce 1 >/dev/null 2>&1
    echo 'Stopped'
    ;;
  *)
    # Invalid usage
    frida --help >&2
    return 255
    ;;
  esac
}
export frida

###############################################################################
### Persistence Handling (mkshrc overlay before reboot)
###############################################################################

SYSTEM_RC='/system/etc'
VENDOR_RC='/vendor/etc'
DEFAULT_RC="$TMPDIR"

# Detect where to install mkshrc based on privilege and layout
function _detect() {
  [ -d "$SYSTEM_RC/bin" ] && echo "$SYSTEM_RC" && return
  [ -d "$VENDOR_RC/bin" ] && echo "$VENDOR_RC" && return

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
    rc_bak="$(mktemp -d)"

    # Copy all existing files from the tmpfs target into the backup directory
    sudo cp -af "$rc_tmpfs"/* "$rc_bak"
    #sudo cp -dprf "$rc_tmpfs"/* "$rc_bak"

    # Mount a tmpfs filesystem over the target directory
    sudo mount -t tmpfs tmpfs "$rc_tmpfs"

    # Restore the backup files into the newly mounted tmpfs
    sudo cp -af "$rc_bak"/* "$rc_tmpfs"
    sudo rm -rf "$rc_bak" # Clean up temporary backup

    # Copy the current mkshrc into tmpfs
    sudo cp -af "$rc_root/mkshrc" "$rc_tmpfs/mkshrc"

    # Copy required binaries into tmpfs/bin
    rc_bin="$rc_tmpfs/bin"
    sudo mkdir -p "$rc_bin"
    for file in busybox curl frida-server openssl libsupol.so supolicy tcpdump update-ca-certificate sqlite3 wlan; do
      [ -f "$rc_root/bin/$file" ] && sudo cp -af "$rc_root/bin/$file" "$rc_bin/$file"
    done

    # Setup BusyBox symlinks
    sudo "$rc_bin/busybox" --install -s "$rc_bin"

    # Set ownership of all files in tmpfs to root:root
    sudo chown -R root:root "$rc_tmpfs"

    # Restoring SELinux objects by default
    # https://cs.android.com/android/platform/superproject/+/master:system/sepolicy/
    sudo chcon -R u:object_r:system_file:s0 "$rc_tmpfs"
    #sudo chcon u:object_r:cgroup_desc_file:s0 "$rc_tmpfs/cgroups.json" >/dev/null 2>&1
    #sudo chcon u:object_r:system_font_fallback_file:s0 "$rc_tmpfs/font_fallback.xml" >/dev/null 2>&1
    #sudo chcon u:object_r:system_event_log_tags_file:s0 "$rc_tmpfs/event-log-tags" >/dev/null 2>&1
    #sudo chcon u:object_r:system_group_file:s0 "$rc_tmpfs/group" >/dev/null 2>&1
    #sudo chcon u:object_r:system_passwd_file:s0 "$rc_tmpfs/passwd" >/dev/null 2>&1
    #sudo chcon -R u:object_r:system_perfetto_config_file:s0 "$rc_tmpfs/perfetto" >/dev/null 2>&1
    #sudo chcon u:object_r:system_linker_config_file:s0 "$rc_tmpfs/ld.config."* >/dev/null 2>&1
    #sudo chcon -R u:object_r:system_seccomp_policy_file:s0 "$rc_tmpfs/seccomp_policy/" >/dev/null 2>&1
    #sudo chcon u:object_r:system_linker_config_file:s0 "$rc_tmpfs/somxreg.conf" >/dev/null 2>&1
    #sudo chcon u:object_r:task_profiles_file:s0 "$rc_tmpfs/task_profiles.json" >/dev/null 2>&1

    # Restore SELinux context for all files in tmpfs
    sudo restorecon -RF "$rc_tmpfs"/* >/dev/null 2>&1

    echo '[I] Script mount permanently until next reboot'
  #else
  #  echo '[D] RC already defined persistently'
  fi

  rc_root="$rc_tmpfs"
else
  echo '[E] RC in persistent mode unavailable' >&2
  echo '[W] Script sets for current shell context only'
fi

rc_bin="$rc_root/bin"

# Add to PATH if not already there
echo "$PATH" | grep -q "$rc_bin" || export PATH="$PATH:$rc_bin"

###############################################################################
### Prompt & Colors
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

###############################################################################
### Tool Fallbacks
###############################################################################

# Provide supolicy fallback (used in Magisk contexts)
_exist magiskpolicy || alias supolicy="LD_LIBRARY_PATH=$rc_bin $rc_bin/supolicy"

# Show IP addresses
alias ipa="$(_resolve ip) a"

# Fix mksh vi mode issues when editing multi-line
function _vi() {
  # https://github.com/matan-h/adb-shell/blob/main/startup.sh#L52
  set +o emacs +o vi-tabcomplete
  "$rc_bin/vi" "$@"
  set -o emacs -o vi-tabcomplete
}
alias vi=_vi

# Fallbacks for common tools if not present
_exist ss || alias ss='netstat'
_exist nc || alias nc='netcat'

# Create a custom colored find command if both find and color support are available
function _cfind() {
  find "$@" | xargs $(_resolve ls) -d1
}

# Enable alias only if 'find' exists and color prompt is enabled
_exist find && [ "$color_prompt" = yes ] && alias cfind=_cfind

# Extract exported vars from init.environ.rc and source them into the current shell
if [ -z "$EXTERNAL_STORAGE" ]; then
  env_check="$TMPDIR/env.rc"
  sudo cat '/init.environ.rc' 2>&1 | grep -- '^ *export ' | awk '{print "export "$2"="$3}' >"$env_check"
  source "$env_check" >/dev/null 2>&1
  rm -rf "$env_check"
fi

# https://xdaforums.com/t/solved-constant-service-provider-update-popup-after-upgrading-to-android-14-rooted-using-magisk.4658043/
_disable 'com.samsung.android.cidmanager' # Samsung CID / device identification & enrollment manager

# https://www.protectstar.com/fr/blog/appcloud-aura-how-invasive-bloatware-spies-on-samsung-users-in-wana
_disable 'com.ironsource.appcloud.oobe'              # IronSource AppCloud OOBE (Sprint / generic operator variants)
_disable 'com.aura.oobe.samsung.gl'                  # Samsung Aura / IronSource OOBE variant (Samsung global)
_disable 'com.ironsource.appcloud.store.lg.vr'       # IronSource AppCloud store (LG / VR variant)
_disable 'com.ironsource.appcloud.appstore.airtelug' # IronSource AppCloud store (Airtel Uganda operator variant)

# Check if the device brand is Samsung
# This prevents running Knox-related commands on non-Samsung devices
if [ "$(getprop ro.product.brand)" = 'samsung' ]; then
  # https://github.com/SolidEva/multidisabler-samsung-keep-encryption/blob/master/META-INF/com/google/android/update-binary
  # Stop the VaultKeeper service
  # VaultKeeper is part of Samsung Knox and communicates with the secure TEE
  # After bootloader unlock, it often fails and spams logcat with errors
  sudo stop vaultkeeper >/dev/null 2>&1

  # Stop the VaultKeeper HAL service (if present on this firmware)
  # This is the hardware abstraction layer interface for VaultKeeper
  # Not all Samsung devices expose this service name
  sudo stop vaultkeeper_hal >/dev/null 2>&1

  # Stop CASS (Context-Aware Security Service)
  # CASS repeatedly checks Knox / VaultKeeper state and retries on failure
  # This is a major source of repeated error logs and wakeup
  sudo stop cass >/dev/null 2>&1

  # https://googleprojectzero.blogspot.com/2020/02/mitigations-are-attack-surface-too.html
  # Stop PROCA (Process Authentication / Runtime Check Agent)
  # PROCA is used by Samsung to monitor process integrity
  # It may interfere with injected or debugged processes
  sudo stop proca >/dev/null 2>&1
fi

# TODO: add persistent history via custom function
# https://github.com/matan-h/adb-shell/blob/main/startup.sh#L73