#!/system/bin/sh

# ==UserScript==
# @name         Android Environment Installer
# @namespace    https://github.com/user/mkshrc/
# @version      1.3
# @description  Install mkshrc shell environment and additional binaries on Android devices
# @author       user
# @match        Android
# ==/UserScript==

# Check if a command exists in PATH
function _exist() {
  command -v "$1" >/dev/null 2>&1
}

# Configurations
TMPDIR='/data/local/tmp'
CPU_ABI="$(getprop ro.product.cpu.abi)"
FRIDA=${1:-'16.7.19'} # Default Frida version if not provided

rc_package="$TMPDIR/package" # Source package folder
rc_bin="$TMPDIR/bin"         # Destination folder for binaries

# Verify CPU ABI support and exit if not supported
[ ! -d "$rc_package/$CPU_ABI" ] && {
  echo "[E] Unsupported CPU ABI architecture: $CPU_ABI"
  exit 1
}

# Clean previous installation and create fresh binary folder
echo '[I] Cleaning previous installation...'
rm -rf "$rc_bin"
mkdir -p "$rc_bin"

# Provide supolicy fallback (used in Magisk contexts)
# https://download.chainfire.eu/1220/SuperSU/
_exist supolicy || {
  echo '[I] Installing supolicy binaries...'
  # https://www.synacktiv.com/en/offers/trainings/android-for-security-engineers
  cp -f "$rc_package/$CPU_ABI/supolicy/supolicy" "$rc_bin/supolicy"
  cp -f "$rc_package/$CPU_ABI/supolicy/libsupol.so" "$rc_bin/libsupol.so"
}

# Install specific Frida server version for the device's CPU ABI
# https://github.com/frida/frida/
echo "[I] Installing Frida server version $FRIDA..."
frida=$(find "$rc_package/$CPU_ABI/frida" -type f -name "frida-server-$FRIDA*android-*")

if [ -z "$frida" ]; then
  echo "[W] Frida version not available: $FRIDA"
else
  cp -f "$frida" "$rc_bin/frida-server"
fi

# Install additional CPU ABI-specific binaries
# https://github.com/topjohnwu/magisk-files/
echo '[I] Installing additional binaries...'
cp -f "$rc_package/$CPU_ABI/busybox/libbusybox.so" "$rc_bin/busybox"
# https://appuals.com/install-curl-openssl-android/
cp -f "$rc_package/$CPU_ABI/curl/curl" "$rc_bin/curl"
cp -f "$rc_package/$CPU_ABI/openssl/openssl" "$rc_bin/openssl"

# Install script for adding root trust CA certificates
cp "$rc_package/update-ca-certificate.sh" "$rc_bin/update-ca-certificate"

# Set ownership and permissions for installed binaries to ensure accessibility
chown -R shell:shell "$rc_bin"
chmod -R 777 "$rc_bin"

# Set up BusyBox command symlinks for all available applets except 'man'
echo '[I] Setting up BusyBox commands...'
busybox="$rc_bin/busybox"
for applet in $("$busybox" --list | grep -vE '^man$'); do
  _exist "$applet" || cp -af "$busybox" "$rc_bin/$applet"
done

# Install RC script to configure shell environment
rc_path="$TMPDIR/mkshrc"
rm "$rc_path"
cp -f "$rc_package/mkshrc.sh" "$rc_path"
echo "[I] RC script installed at $rc_path"

# Load RC script to configure shell environment
echo '[I] Loading shell environment...'
source "$rc_path"

# Clean up the deployment package after installation
echo '[I] Cleaning up deployment package...'
rm -rf "$rc_package" "$TMPDIR/install.sh"

echo '[I] Installation completed successfully'
