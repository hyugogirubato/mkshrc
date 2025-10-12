@echo off
:: mkshrc install helper (Windows .bat)
:: PURPOSE:
::   Push the mkshrc package to a single Android device over ADB.
::   - Intended for interactive use on one connected device.
::   - Automatically selects the package subfolder matching the device ABI.
::   - Quietly removes previous temp/install locations before pushing files.
::
:: IMPORTANT NOTES:
::   - This script assumes package/<ABI> contains the prebuilt binaries for that ABI
::     (for example package/arm64-v8a). If your folder is named differently adjust the
::     adb push line accordingly.
::   - The script requires exactly ONE device connected. If you need to target a
::     specific device when multiple are connected, use `adb -s <serial> ...` instead
::     of plain `adb` and adapt the script accordingly.
::   - Some commands (rm -rf on system paths, persistent installs) may require root
::     on the device; this script only pushes files into /data/local/tmp by default.

REM ---------- Basic checks ----------
REM Ensure adb is installed and start the daemon (helps with some Windows setups)
adb start-server >nul 2>&1
if ERRORLEVEL 1 (
  echo ERROR: adb not found in PATH. Install Android Platform Tools and retry.
  exit /b 1
)

REM ---------- Device count check ----------
REM We only allow exactly one 'device' state entry to avoid pushing to multiple targets.
REM 'adb devices' prints a header line and one line per device; this loop counts lines with status "device".
set cnt=0
for /f "tokens=1,2" %%a in ('adb devices') do (
  if "%%b"=="device" set /a cnt+=1
)

if %cnt%==0 (
  echo ERROR: No connected devices. Connect one device and enable ADB.
  exit /b 1
)

if %cnt% GTR 1 (
  echo ERROR: More than one device connected. This script works only with one device.
  echo        To target a specific device, run commands manually with:
  echo        adb -s <serial> push ...
  exit /b 1
)

REM ---------- Architecture (ABI) check ----------
REM Query the device for its primary CPU ABI. We use this to pick the right package subfolder.
REM Common values: arm64-v8a, armeabi-v7a, x86, x86_64, etc.
for /f "usebackq delims=" %%a in (`adb shell getprop ro.product.cpu.abi 2^>nul`) do set ABI=%%a

if "%ABI%"=="" (
  echo ERROR: Failed to detect device ABI.
  exit /b 1
)

echo Detected device ABI: %ABI%

REM If your package folders use different naming (e.g., arm64 instead of arm64-v8a),
REM you can map ABI here. Example mapping (uncomment and adapt if needed):
REM if "%ABI%"=="aarch64" set ABI=arm64-v8a
REM if "%ABI%"=="arm64" set ABI=arm64-v8a

REM ---------- Proceed with install (safe) ----------
REM Remove old temporary paths where previous installs stored files.
REM Redirect output to nul to avoid clutter; remove redirection if you want verbose output.
adb shell rm -rf /data/local/tmp/bin /data/local/tmp/package /data/local/tmp/mkshrc /system/etc/bin /vendor/etc/bin >nul 2>&1

REM Ensure target directory exists before pushing files.
adb shell mkdir -p /data/local/tmp/package

REM ---------- Push appropriate ABI package ----------
REM This will push the folder package/%ABI% — ensure it exists locally.
REM If you want to force a specific ABI regardless of device, replace %ABI% with your folder name.
adb push package/%ABI% /data/local/tmp/package

REM ---------- Push helper scripts ----------
REM These are architecture-independent shell scripts used by mkshrc.
adb push package/mkshrc.sh /data/local/tmp/package
adb push package/update-ca-certificate.sh /data/local/tmp/package
adb push package/wlan.sh /data/local/tmp/package

REM Push the installer entrypoint. We write it to /data/local/tmp/mkshrc so the user
REM can `source /data/local/tmp/mkshrc` from adb shell as described in the README.
adb push install.sh /data/local/tmp/mkshrc

echo Done.
echo NOTE: Source the environment in a device shell with:
echo       adb shell
echo       source /data/local/tmp/mkshrc

:: If you want to inspect pushed files locally use:
::   adb shell ls -l /data/local/tmp/package
::   adb shell ls -l /data/local/tmp/mkshrc