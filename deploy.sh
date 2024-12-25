#!/bin/env bash

# =======================
# Linux Script to Deploy Files to Android Devices
# =======================

# Check if a serial number is provided as an argument
if [ $# -gt 1 ]; then
  echo "Usage: $0 [serial]"
  exit 1
fi

# Define variables for binary names
busybox='busybox-1.36.1.1-arm64-v8a.so'
frida='frida-server-16.5.9-android-arm64'

# Decompress frida-server if compressed
[ -f "$frida.xz" ] && xz -d "$frida.xz"

# Check if adb is installed, if not, install it
if ! command -v adb &> /dev/null; then
  sudo apt update
  sudo apt install adb -y
fi

# Start ADB server if not already running
adb start-server

# Get the list of connected devices
devices=$(adb devices | tail -n +2) # Exclude header line

# Determine the device to work with
if [ -n "$1" ]; then
  # User provided a serial number
  device=$(echo "$devices" | grep "$1")
elif [ $(echo "$devices" | wc -l) -gt 1 ]; then
  # Multiple devices detected, exit and ask user to specify
  echo 'Multiple devices detected. Please provide a serial number.'
  exit 2
else
  # Use the first connected device
  device=$(echo "$devices" | head -n +1)
fi

# Validate the device
if [ -z "$device" ]; then
  echo 'No devices found.'
  exit 3
elif ! echo "$device" | grep -q 'device'; then
  status=$(echo "$device" | awk -F '\t' '{print $2}')
  echo "Invalid device status: $status"
  exit 4
fi

# Extract the serial number of the selected device
serial=$(echo "$device" | awk -F '\t' '{print $1}')
echo "Selected device: $serial"

# Prepare directories on the device
TMPDIR='/data/local/tmp'
adb -s "$serial" shell mkdir -p "$TMPDIR/bin"

# Push binaries and scripts to the device
adb -s "$serial" push 'mkshrc' "$TMPDIR/mkshrc"
adb -s "$serial" push "$busybox" "$TMPDIR/bin/busybox"
adb -s "$serial" push "$frida" "$TMPDIR/frida-server"

echo 'Deployment completed successfully.'

