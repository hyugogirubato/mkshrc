@echo off

:: =======================
:: Windows Batch Script to Deploy Files to Android Devices
:: =======================

:: Check if ADB is installed
where adb >nul 2>nul
if %errorlevel% neq 0 (
    echo ADB is not installed. Please install it first.
    exit /b 1
)

:: # Start ADB server if not already running
adb start-server

:: Get the list of connected devices
set "device="
set "status="
for /f "tokens=1,2 delims=	" %%A in ('adb devices ^| findstr /v "List of devices attached"') do (
    set "device=%%A"
    set "status=%%B"
)

:: Check if any device is connected
if "%device%"=="" (
    echo No devices found.
    exit /b 1
)

:: Trim whitespace from status and check device status
for /f "delims=" %%S in ("%status%") do set "status=%%S"
if not "%status%"=="device" (
    echo Invalid device status: %status%
    exit /b 2
)

:: Select the first connected device (or specific serial if provided as argument)
if "%~1" neq "" (
    set "serial=%~1"
) else (
    set "serial=%device%"
)

echo Selected device: %serial%

:: Prepare directories on the device
set "TMPDIR=/data/local/tmp"
adb -s "%serial%" shell mkdir -p "%TMPDIR%/bin"

:: Push files to the device
adb -s "%serial%" push "mkshrc" "%TMPDIR%/mkshrc"
adb -s "%serial%" push "frida-server-16.5.9-android-arm64" "%TMPDIR%/bin/frida-server"
adb -s "%serial%" push "busybox-1.36.1.1-arm64-v8a.so" "%TMPDIR%/bin/busybox"

echo Deployment completed successfully.
exit /b 0
