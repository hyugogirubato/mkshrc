#!/system/bin/sh

# ==UserScript==
# @name         Android Environment Installer
# @namespace    https://github.com/user/mkshrc/
# @version      1.5
# @description  Install mkshrc shell environment and additional binaries on Android devices
# @author       user
# @match        Android
# ==/UserScript==

# Configurations
TMPDIR='/data/local/tmp'
CPU_ABI="$(getprop ro.product.cpu.abi)"
FRIDA=${1:-'17.5.1'} # Default Frida version if not provided

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

# Install supolicy (SELinux policy tool)
# Provides fallback when Magisk’s magiskpolicy is not available
# https://download.chainfire.eu/1220/SuperSU/
echo '[I] Installing supolicy binaries...'
# https://www.synacktiv.com/en/offers/trainings/android-for-security-engineers
cp -f "$rc_package/$CPU_ABI/supolicy/supolicy" "$rc_bin/supolicy"
cp -f "$rc_package/$CPU_ABI/supolicy/libsupol.so" "$rc_bin/libsupol.so"

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
echo '[I] Installing additional binaries...'
# https://github.com/topjohnwu/magisk-files/
cp -f "$rc_package/$CPU_ABI/busybox/libbusybox.so" "$rc_bin/busybox"
# https://appuals.com/install-curl-openssl-android/
cp -f "$rc_package/$CPU_ABI/curl/curl" "$rc_bin/curl"
cp -f "$rc_package/$CPU_ABI/openssl/openssl" "$rc_bin/openssl"
# https://android.googlesource.com/platform/external/tcpdump.git/+/refs/heads/android14-qpr2-release/INSTALL.md
cp -f "$rc_package/$CPU_ABI/tcpdump/tcpdump" "$rc_bin/tcpdump"
# https://github.com/EXALAB/sqlite3-android
cp -f "$rc_package/$CPU_ABI/sqlite3/sqlite3" "$rc_bin/sqlite3"

# Install script for adding root trust CA certificates
cp -f "$rc_package/update-ca-certificate.sh" "$rc_bin/update-ca-certificate"

# Install wlan utility to dump configured Wi‑Fi networks
cp -f "$rc_package/wlan.sh" "$rc_bin/wlan"

# Set ownership and permissions for installed binaries to ensure accessibility
chown -R shell:shell "$rc_bin"
chmod -R 777 "$rc_bin"

# Set up BusyBox command symlinks for all available applets
# Makes applets callable directly via PATH (system binaries still take priority)
echo '[I] Setting up BusyBox commands...'
"$rc_bin/busybox" --install -s "$rc_bin"

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
