# mkshrc – Android Shell Environment

`mkshrc` provides a simple, user-friendly shell environment for Android. It bundles a minimal UNIX-like toolbox (BusyBox, OpenSSL, curl, frida-server, supolicy, etc.) and installs an RC script that improves usability.

## Features

* User-friendly shell interface with `mkshrc`
* Pre-packaged command-line tools (BusyBox, curl, OpenSSL, frida-server, supolicy, tcpdump, sqlite)
* Auto-symlinks for BusyBox applets
* Certificate injection helper (`update-ca-certificate`)
* Wi‑Fi inspection tool (`wlan`) - dumps saved networks
* Works on rooted *and* non-rooted devices (behavior differs, see Usage)

## Included Binaries

| Binary       | Version                   | Notes                             |
|--------------|---------------------------|-----------------------------------|
| BusyBox      | 1.36.1.1                  | Multi-call binary with core tools |
| OpenSSL      | 1.1.1l (NDK 23.0.7599858) | Cryptography and TLS toolkit      |
| cURL         | 7.78.0 (NDK 23.0.7599858) | Command-line HTTP/HTTPS client    |
| frida-server | 17.2.17, 16.7.9           | Dynamic instrumentation toolkit   |
| Supolicy     | 2.82                      | SELinux policy helper             |
| Tcpdump      | 4.9.2 (NDK 18.1.5063045)  | Network packet analyzer           |
| SQLite       | 3.22.0 (NDK 16.1.4479499) | Command-line database utility     |

## Quick install

1. Push the installer package to your device:

   ```bat
   adb push package/ /data/local/tmp/
   adb push install.sh /data/local/tmp/mkshrc
   ```

   (An included `install.bat` automates this on Windows)

2. Open a shell on your device:

   ```sh
   adb shell
   ```

3. Source the installer/environment:

   ```sh
   source /data/local/tmp/mkshrc
   ```

# Usage / behavior

* **Rooted devices**
  The script mounts itself permanently, so future shells automatically include it.

* **Non-rooted devices**
  `source /data/local/tmp/mkshrc` must be run in every new shell session to enable the environment and utilities.

## Extra Utilities

* `update-ca-certificate <path>` – install custom CA certificates into the Android system trust store.
* `restart` – perform a **soft reboot** of the Android framework (required root).
* `pull <path>` – safely copy a file from the system into `/data/local/tmp/`.
* `frida {start|status|stop|version}` – manage the Frida server lifecycle.
* BusyBox applets are symlinked automatically (except `man`).
* `wlan` — show saved Wi‑Fi networks (SSID, PSK, security, hidden).

# Examples

Start frida:

```sh
source /data/local/tmp/mkshrc
frida start
frida status
```

Copy a protected file out safely:

```sh
source /data/local/tmp/mkshrc
pull /data/misc/wifi/wpa_supplicant.conf
exit
adb pull /data/local/tmp/wpa_supplicant.conf .
```

Install a CA (example):

```sh
source /data/local/tmp/mkshrc
update-ca-certificate ./my-ca.pem
```

# Security & privacy

* Many utilities interact with sensitive device data (Wi-Fi credentials, certificates, network traffic). Use only on devices you own or with explicit permission.
* Avoid distributing credentials or device-specific files you extract with this tool.

## Disclaimer

This project is intended for **educational and debugging purposes only**. Using these tools may modify your Android device. Proceed at your own risk.