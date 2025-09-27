# mkshrc – Android Shell Environment

`mkshrc` provides a more user-friendly shell environment on Android devices. It installs a minimal UNIX-like toolbox (BusyBox, OpenSSL, curl, Frida, supolicy) along with a shell RC script that improves usability.

## Features

* User-friendly shell interface with `mkshrc`
* Pre-packaged common tools (BusyBox, curl, OpenSSL, Frida, supolicy)
* Auto-symlinks for BusyBox applets
* Certificate injection helper (`update-ca-certificate`)
* Wi‑Fi inspection tool (`wlan`) - dumps saved networks
* Works on both rooted and non-rooted devices

## Included Binaries

| Binary       | Version                   | Notes                    |
|--------------|---------------------------|--------------------------|
| BusyBox      | 1.36.1.1                  | Full applet support      |
| OpenSSL      | 1.1.1l (NDK 23.0.7599858) | Built with Android NDK   |
| curl         | 7.78.0 (NDK 23.0.7599858) | With SSL support         |
| frida-server | 17.2.17, 16.7.9           | Choose version as needed |
| supolicy     | 2.82                      | SELinux policy helper    |
| tcpdump      | 4.9.2 (NDK 18.1.5063045)  | Network packet analyzer  |

## Installation

1. Push the installer package to your device:

   ```bat
   adb push package/ /data/local/tmp/
   adb push install.sh /data/local/tmp/mkshrc
   ```

   or use the included `install.bat`.

2. Open a shell on your device:

   ```sh
   adb shell
   ```

3. Run the installer:

   ```sh
   source /data/local/tmp/mkshrc
   ```

## Usage

When you open an `adb shell`, you must source the environment:

```sh
source /data/local/tmp/mkshrc
```

* **If the device is rooted**:
  The script mounts itself permanently, so future shells automatically include it.

* **If the device is not rooted**:
  You must manually `source /data/local/tmp/mkshrc` in each new shell session.

## Extra Utilities

* `update-ca-certificate <path>` – install custom CA certificates into the Android system trust store.
* `restart` – perform a **soft reboot** of the Android framework (required root).
* `pull <path>` – safely copy a file from the system into `/data/local/tmp/`.
* `frida {start|status|stop|version}` – manage the Frida server lifecycle.
* BusyBox applets are symlinked automatically (except `man`).
* `wlan` — show saved Wi‑Fi networks (SSID, PSK, security, hidden).

## Disclaimer

This project is intended for **educational and debugging purposes only**. Using these tools may modify your Android device. Proceed at your own risk.