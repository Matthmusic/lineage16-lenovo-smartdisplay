LOCAL_PATH := device/lenovo/blueberry

# A/B OTA
AB_OTA_UPDATER := true
AB_OTA_PARTITIONS := boot system vendor

AB_OTA_POSTINSTALL_CONFIG += \
    RUN_POSTINSTALL_system=true \
    POSTINSTALL_PATH_system=system/bin/otapreopt_script \
    FILESYSTEM_TYPE_system=ext4 \
    POSTINSTALL_OPTIONAL_system=true

PRODUCT_PACKAGES += \
    otapreopt_script \
    update_engine \
    update_engine_sideload \
    update_verifier

# Filesystems
PRODUCT_PACKAGES += \
    fs_config_files

# Init scripts
PRODUCT_PACKAGES += \
    init.msm8x53.rc \
    init.msm8x53.usb.rc \
    fstab.msm8x53 \
    ueventd.msm8x53.rc

PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/rootdir/etc/fstab.msm8x53:$(TARGET_COPY_OUT_RAMDISK)/fstab.msm8x53 \
    $(LOCAL_PATH)/rootdir/etc/fstab.msm8x53:$(TARGET_COPY_OUT_VENDOR)/etc/fstab.msm8x53 \
    $(LOCAL_PATH)/rootdir/etc/init.msm8x53.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/init.msm8x53.rc \
    $(LOCAL_PATH)/rootdir/etc/init.msm8x53.usb.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/init.msm8x53.usb.rc \
    $(LOCAL_PATH)/rootdir/etc/ueventd.msm8x53.rc:$(TARGET_COPY_OUT_VENDOR)/ueventd.rc

# Display
PRODUCT_PROPERTY_OVERRIDES += \
    ro.sf.lcd_density=240 \
    ro.sf.hwrotation=270 \
    debug.sf.hw=1 \
    debug.egl.hw=1 \
    persist.hwc.mdpcomp.enable=true

# USB via ConfigFS (ce kernel n'a pas le gadget android_usb legacy)
PRODUCT_PROPERTY_OVERRIDES += \
    sys.usb.controller=7000000.dwc3 \
    sys.usb.rndis.func.name=gsi \
    sys.usb.rmnet.func.name=gsi

# ADB
PRODUCT_PROPERTY_OVERRIDES += \
    ro.adb.secure=0 \
    ro.secure=0 \
    ro.debuggable=1

# Platform Qualcomm
PRODUCT_PROPERTY_OVERRIDES += \
    ro.vendor.qti.va_aosp.support=1 \
    dalvik.vm.heapstartsize=8m \
    dalvik.vm.heapgrowthlimit=192m \
    dalvik.vm.heapsize=512m \
    dalvik.vm.heaptargetutilization=0.75 \
    dalvik.vm.heapminfree=512k \
    dalvik.vm.heapmaxfree=8m

# Bluetooth
PRODUCT_PROPERTY_OVERRIDES += \
    qcom.bluetooth.soc=cherokee

# WiFi
PRODUCT_PACKAGES += \
    hostapd \
    wpa_supplicant \
    wpa_supplicant.conf

# Audio
PRODUCT_PROPERTY_OVERRIDES += \
    ro.config.media_vol_steps=25 \
    ro.config.vc_call_vol_steps=7

# Shipping API
PRODUCT_SHIPPING_API_LEVEL := 27

# VNDK
PRODUCT_TARGET_VNDK_VERSION := 27
