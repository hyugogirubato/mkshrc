#!/system/bin/sh

# ==UserScript==
# @name         update-ca-certificates
# @namespace    https://github.com/user/mkshrc/
# @version      1.5
# @description  Inject custom CA certificates into Android system trust store
# @author       user
# @match        Android
# ==/UserScript==

# Import helper functions (e.g. sudo wrapper) from user environment
[ -d '/system/etc/bin' ] && rc_path='/system/etc/mkshrc' || rc_path="$TMPDIR/mkshrc"
[ -d '/vendor/etc/bin' ] && rc_path='/vendor/etc/mkshrc'
source "$rc_path" >/dev/null 2>&1

# Define certificate store locations
CERT_APEX='/apex/com.android.conscrypt/cacerts'
CERT_SYSTEM='/system/etc/security/cacerts'

# Bind system certs into the mount namespace of the given process
function mntns() {
  local NS="/proc/$1/ns/mnt"

  # Check if CERT_APEX is already mounted in this namespace
  if ! sudo nsenter --mount="$NS" -- /bin/mount | grep -q -- " $CERT_APEX "; then
    # Bind-mount system certs into the APEX cert directory
    sudo nsenter --mount="$NS" -- /bin/mount --bind "$CERT_SYSTEM" "$CERT_APEX"
  fi
}

# Input certificate sanity check
crt_path="${1?'Missing certificate path'}"
[ -f "$crt_path" ] || {
  echo "Missing or inaccessible file path: $crt_path" >&2
  exit 1
}

# Verify that the current user has root privileges
[ "$(sudo id -un 2>&1)" = 'root' ] || {
  echo 'Permission denied. Privileged user not available.' >&2
  exit 1
}

# Normalize line endings (some certs copied from Windows may break openssl)
dos2unix "$crt_path"

# Compute the OpenSSL hash (used as filename in system certs)
crt_hash="$(openssl x509 -inform PEM -subject_hash_old -in "$crt_path" -noout 2>&1)"
if [ -z "$crt_hash" ] || [ "${#crt_hash}" -ne 8 ]; then
  echo "$crt_hash" >&2
  exit 1
fi
crt_name="$crt_hash.0"

# If already present, exit early
[ -f "$CERT_SYSTEM/$crt_name" ] && {
  echo "Certificate already installed: $CERT_SYSTEM/$crt_name"
  exit 0
}

echo "Updating certificates in $CERT_SYSTEM..."

# https://github.com/user/JustTrustMe
# Prepare new certificate file
hash_path="$TMPDIR/$crt_name"
openssl x509 -in "$crt_path" >"$hash_path"
openssl x509 -in "$crt_path" -fingerprint -text -noout >>"$hash_path"

# Temporary file path we'll use to check writability of the system cert dir.
# If we can successfully create this file, we know CERT_SYSTEM is writable.
crt_check="$CERT_SYSTEM/00000000.0"

# If the directory is not writable (touch fails) we need to remount it:
if ! sudo touch "$crt_check" >/dev/null 2>&1; then
  # https://github.com/httptoolkit/httptoolkit-server/blob/main/src/interceptors/android/adb-commands.ts#L427
  # Create a separate temp directory, to hold the current certificates
  # Without this, when we add the mount we can't read the current certs anymore.
  crt_bak="$(mktemp -d)"

  # Copy out the existing certificates
  if [ -d "$CERT_APEX" ]; then
    sudo cp -af "$CERT_APEX"/* "$crt_bak"
  else
    sudo cp -af "$CERT_SYSTEM"/* "$crt_bak"
  fi

  # Create the in-memory mount on top of the system certs folder
  sudo mount -t tmpfs tmpfs "$CERT_SYSTEM"

  # Copy the existing certs back into the tmpfs mount, so we keep trusting them
  sudo cp -af "$crt_bak"/* "$CERT_SYSTEM"

  # Delete the temp cert directory & this script itself
  rm -rf "$crt_bak"
fi

# Clean up the temporary test file if it was created.
sudo rm -rf "$crt_check"

# Copy our new cert in, so we trust that too
sudo mv "$hash_path" "$CERT_SYSTEM"

# Update the perms & selinux context labels, so everything is as readable as before
sudo chown -R root:root "$CERT_SYSTEM"
sudo chmod 644 "$CERT_SYSTEM"/*

sudo chcon -R u:object_r:system_file:s0 "$CERT_SYSTEM"
#sudo chcon -R u:object_r:system_security_cacerts_file:s0 "$CERT_SYSTEM" >/dev/null 2>&1

# Restore SELinux context for all certificate files
sudo restorecon -RF "$CERT_SYSTEM"/* >/dev/null 2>&1

echo '1 added, 0 removed; done.'

# Deal with the APEX overrides in Android 14+, which need injecting into each namespace:
if [ -d "$CERT_APEX" ]; then
  echo 'Running hooks for APEX namespaces...'

  # When the APEX manages cacerts, we need to mount them at that path too. We can't do
  # this globally as APEX mounts are namespaced per process, so we need to inject a
  # bind mount for this directory into every mount namespace.

  # First we mount for the shell itself, for completeness, and so we can see this
  # when we check for correct installation on later runs
  if ! mount | grep -q -- " $CERT_APEX "; then
    sudo mount --bind "$CERT_SYSTEM" "$CERT_APEX" 2>/dev/null || true
  fi

  # First we get the Zygote process(es), which launch each app
  ZYGOTE_PID=$(pidof zygote || true)
  ZYGOTE64_PID=$(pidof zygote64 || true)
  Z_PIDS="$ZYGOTE_PID $ZYGOTE64_PID"
  # N.b. some devices appear to have both, some have >1 of each (!)

  # Apps inherit the Zygote's mounts at startup, so we inject here to ensure all newly
  # started apps will see these certs straight away:
  for Z_PID in $Z_PIDS; do
    [ -n "$Z_PID" ] && mntns "$Z_PID" >/dev/null 2>&1
  done

  echo 'Zygote APEX certificates remounted'

  # Then we inject the mount into all already running apps, so they see these certs immediately.

  # Get the PID of every process whose parent is one of the Zygotes:
  APP_PIDS=$(echo "$Z_PIDS" | xargs -n1 ps -o PID -P | grep -v PID)

  # Inject into the mount namespace of each of those processes.
  # We do this in small batches to avoid overloading weak kernels:
  # - Full parallel nsenter can trigger hangs or soft reboots on some devices
  # - Sequential injection is safe but slow
  # - Batched execution provides a good balance between speed and stability

  # Maximum number of concurrent nsenter operations
  MAX_JOBS=4

  job_count=0 # Number of active background jobs in the current batch
  app_count=0 # Total number of processes successfully targeted
  for PID in $APP_PIDS; do
    # Skip processes that exited between enumeration and injection
    [ -d "/proc/$PID" ] || continue

    # Inject the bind mount into this process's mount namespace
    (mntns "$PID" >/dev/null 2>&1) &

    job_count=$((job_count + 1))
    app_count=$((app_count + 1))

    # When the batch limit is reached, wait for all jobs to complete
    if [ "$job_count" -ge "$MAX_JOBS" ]; then
      wait
      job_count=0
    fi
  done

  # Wait for any remaining background jobs
  wait

  echo "APEX certificates remounted for $app_count apps"
fi

echo 'done.'
