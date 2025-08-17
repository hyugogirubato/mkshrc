@echo off

adb shell rm -rf /data/local/tmp/bin /data/local/tmp/mkshrc /system/etc/bin /vendor/etc/bin /data/local/tmp/package
adb shell mkdir -p /data/local/tmp/package

adb push package/arm64-v8a /data/local/tmp/package
adb push package/mkshrc.sh /data/local/tmp/package
adb push package/update-ca-certificate.sh /data/local/tmp/package

adb push install.sh /data/local/tmp/mkshrc