# mkshrc: Advanced Shell Environment for Android Devices

Project mkshrc provides a feature-rich shell environment for Android devices, enhancing usability and productivity by offering convenience aliases, support for essential tools like BusyBox and Frida server, and a streamlined deployment process. It supports both rooted and non-rooted devices, with easy configuration using ADB.

---

## Features and Improvements

### Key Features:
1. **Enhanced Shell Environment**:
   - **Aliases** for common commands with colorized output for better readability (`ls`, `grep`, `logcat`, etc.).
   - Convenient shortcuts (`ll`, `la`, `l`, etc.) for streamlined navigation and operations.
   - Auto-detection of essential environment variables (`USER`, `HOSTNAME`, `TMPDIR`, etc.).

2. **BusyBox Integration**:
   - Automatically deploys BusyBox and creates symlinks for its utilities.
   - Ensures availability of essential Unix commands on the Android shell.

3. **Frida Server Management**:
   - Simplifies the process of starting, stopping, and monitoring the Frida server.
   - Automatic SELinux permissive mode adjustment for compatibility.

4. **Custom Commands**:
   - **`man`**: Simulates manual page functionality using `--help` outputs.
   - **`sudo`**: Adds `sudo`-like functionality for non-root users, enabling command execution via `su`.

5. **Cross-Compatible**:
   - Works seamlessly on rooted and non-rooted Android devices.
   - Usable after every ADB session by sourcing the `mkshrc` script.

---

### Deployment Enhancements:
- **Deployment Scripts**:
  - Automated deployment using `deploy.bat` (Windows) or `deploy.sh` (Linux).
  - Pushes required binaries (`frida-server`, `busybox`) and configuration files (`mkshrc`) to the device.

- **Manual Loading**:
  - Load `mkshrc` manually:
    ```sh
    adb shell
    source /data/local/tmp/mkshrc
    ```

### Improvements:
- Integrated support for SELinux adjustments for Frida server operations.
- Automatic BusyBox utility linking, reducing manual setup.
- Supports deployment with minimal prerequisites, ensuring a consistent environment across devices.

---

## Prerequisites

1. **Tools**:
   - ADB installed on your computer.
   - For rooted devices, ensure you have `su` access.
   - Compatible binaries for your Android architecture (links provided below).

2. **Binaries**:
   - [Frida Server](https://github.com/frida/frida/releases/download/16.5.9/frida-server-16.5.9-android-arm64.xz):
     - Download and extract `frida-server-16.5.9-android-arm64.xz` to obtain the `frida-server` binary.
   - [BusyBox](https://github.com/topjohnwu/magisk-files/releases/download/files/busybox-1.36.1.1.zip):
     - Extract and use the `busybox-1.36.1.1-arm64-v8a.so` binary, renamed as `busybox`.

---

## Deployment Instructions

### Automated Deployment:
1. **Run Deployment Scripts**:
   - **Windows**:
     ```cmd
     deploy.bat [serial]
     ```
   - **Linux**:
     ```sh
     ./deploy.sh [serial]
     ```
   If multiple devices are connected, specify the serial ID. 

2. **Deployment Summary**:
   - The script pushes:
     - `mkshrc` to `/data/local/tmp/`.
     - Binaries (`frida-server`, `busybox`) to `/data/local/tmp/bin/`.
   - Sets proper ownership and permissions for all files.

---

### Manual Deployment:
1. **Prepare Directories**:
   - Create a directory for binaries:
     ```sh
     adb shell mkdir -p /data/local/tmp/bin
     ```

2. **Push Files**:
   - Transfer required binaries and configuration files:
     ```sh
     adb push busybox /data/local/tmp/bin/
     adb push frida-server /data/local/tmp/bin/
     adb push mkshrc /data/local/tmp/
     ```

3. **Set Permissions**:
   - Ensure binaries are executable:
     ```sh
     adb shell chmod +x /data/local/tmp/bin/*
     ```

---

## Usage

### Loading the Environment:
1. Connect to your device using ADB:
   ```sh
   adb shell
   ```

2. Source the `mkshrc` file to initialize:
   ```sh
   source /data/local/tmp/mkshrc
   ```

### Commands Overview:
- **BusyBox Utilities**:
  Access all BusyBox commands directly after deployment.
  ```sh
  ls | grep busybox
  ```

- **Frida Server Management**:
  - Start Frida:
    ```sh
    frida start
    ```
  - Check status:
    ```sh
    frida status
    ```
  - Stop Frida:
    ```sh
    frida stop
    ```

- **Aliases and Utilities**:
  - Example:
    ```sh
    ll   # List files with detailed information.
    grep 'pattern' file.txt
    ```

- **Custom Commands**:
  - Manual pages:
    ```sh
    man ls
    ```
  - Sudo (non-root):
    ```sh
    sudo ls /data/data
    ```

---

## Notes

- Always decompress any compressed binaries (e.g., `xz -d frida-server.xz`) before deployment.
- For rooted devices, gain `su` access for enhanced functionality.
- Ensure `mkshrc` is sourced after every ADB session to enable its environment.

## Licensing

This software is licensed under the terms of [MIT License](https://github.com/hyugogirubato/mkshrc/blob/main/LICENSE).  
You can find a copy of the license in the LICENSE file in the root folder.

---

© hyugogirubato 2024