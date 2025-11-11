#!/system/bin/sh

# ==UserScript==
# @name         wlan
# @namespace    https://github.com/user/mkshrc/
# @version      1.1
# @description  Extract configured Wi-Fi networks (XML or wpa_supplicant)
# @author       user
# @match        Android
# ==/UserScript==

# Import helper functions (e.g. sudo wrapper) from user environment
[ -d '/system/etc/bin' ] && rc_path='/system/etc/mkshrc' || rc_path="$TMPDIR/mkshrc"
[ -d '/vendor/etc/bin' ] && rc_path='/vendor/etc/mkshrc'
source "$rc_path" >/dev/null 2>&1

# Wi-Fi configuration paths
WIFI_STORE='/data/misc/wifi/WifiConfigStore.xml'
WIFI_APEX='/data/misc/apexdata/com.android.wifi/WifiConfigStore.xml'
WIFI_WPA='/data/misc/wif/wpa_supplicant.conf'

# Verify that the current user has root privileges
[ "$(sudo id -un 2>&1)" = 'root' ] || {
  echo 'Permission denied. Privileged user not available.' >&2
  exit 1
}

# Read Wi-Fi configuration from the first available path
content=''
for path in "$WIFI_APEX" "$WIFI_STORE" "$WIFI_WPA"; do
  if sudo stat "$path" >/dev/null 2>&1; then
    echo "Using Wi-Fi configuration from: $path"
    content="$(sudo cat "$path")" && break
  fi
done

[ -z "$content" ] && {
  echo 'No Wi-Fi configuration found' >&2
  exit 1
}

# Extract SSID, PSK, security, and hidden flag depending on format
if echo "$content" | grep -q '^<?xml'; then
  # XML format (WifiConfigStore.xml)
  # https://blog.digital-forensics.it/2024/02/dissecting-android-wificonfigstorexml.html
  ssid_list="$(echo "$content" | grep '<string name="SSID">' | sed -E 's/.*&quot;([^&]+)&quot;.*/\1/')"
  psk_list=$(echo "$content" | grep -E '<string name="PreSharedKey">|<null name="PreSharedKey"' | sed -E 's/.*<string name="PreSharedKey">&quot;([^&]*)&quot;.*/\1/; t; s/.*<null name="PreSharedKey".*/NONE/')
  sec_list="$(echo "$content" | grep '<string name="ConfigKey">' | sed -E 's/.*&quot;[^&]+&quot;([A-Z_]+).*/\1/')"
  hidden_list="$(echo "$content" | grep '<boolean name="HiddenSSID"' | sed -E 's/.*value="(true|false)".*/\1/')"
else
  # wpa_supplicant.conf format
  # https://git.w1.fi/cgit/hostap/plain/wpa_supplicant/wpa_supplicant.conf
  ssid_list=$(echo "$content" | grep -E '^\s*ssid=' | sed -E 's/^\s*ssid="?(.*)"?/\1/')
  psk_list=$(echo "$content" | grep -E '^\s*psk=|^\s*key_mgmt=NONE' | sed -E 's/^\s*psk="?(.*)"?/\1/; t; s/.*/NONE/')
  sec_list=$(echo "$content" | grep -E '^\s*key_mgmt=' | sed -E 's/^\s*key_mgmt=(.*)/\1/')
  hidden_list=$(echo "$content" | grep -E '^\s*scan_ssid=' | sed -E 's/^\s*scan_ssid=([01])/\1/; t; s/.*/0/' | sed -E 's/1/true/; s/0/false/')
fi

if [ -z "$ssid_list" ]; then
  echo 'No registered Wi-Fi networks found.' >&2
  exit 2
fi

# Output each network line by line
echo "Registered Wi-Fi networks:"
i=1
echo "$ssid_list" | while read ssid; do
  psk="$(echo "$psk_list" | sed -n "${i}p")"
  sec="$(echo "$sec_list" | sed -n "${i}p")"
  hidden="$(echo "$hidden_list" | sed -n "${i}p")"
  [ -z "$hidden" ] && hidden=false
  echo "[$i] SSID: $ssid"
  echo "    Password: $psk"
  echo "    Security: $sec"
  echo "    HiddenSSID: $hidden"
  echo "------------------------------------"
  #echo "SSID: $ssid, Password: $psk, Security: $sec, HiddenSSID: $hidden"
  i=$((i + 1))
done
