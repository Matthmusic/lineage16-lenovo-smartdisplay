LOCAL_PATH := device/lenovo/blueberry

# Architecture (32-bit ARM pour MSM8953 Android Things)
TARGET_ARCH := arm
TARGET_ARCH_VARIANT := armv7-a-neon
TARGET_CPU_ABI := armeabi-v7a
TARGET_CPU_ABI2 := armeabi
TARGET_CPU_VARIANT := cortex-a53

# Bootloader
TARGET_BOOTLOADER_BOARD_NAME := msm8953
TARGET_NO_BOOTLOADER := true

# Kernel - utilise le kernel natif extrait de l'appareil
TARGET_PREBUILT_KERNEL := device/lenovo/blueberry/prebuilt/zImage
BOARD_KERNEL_CMDLINE := console=ttyMSM0,115200,n8 earlyprintk androidboot.hardware=msm8x53 androidboot.bootdevice=7824900.sdhci firmware_class.path=/oem/firmware androidboot.selinux=permissive
BOARD_KERNEL_BASE := 0x10000000
BOARD_KERNEL_PAGESIZE := 2048
BOARD_KERNEL_TAGS_OFFSET := 0x00000100
BOARD_RAMDISK_OFFSET := 0x01000000
BOARD_MKBOOTIMG_ARGS := --ramdisk_offset 0x01000000 --tags_offset 0x00000100

# Partitions A/B
AB_OTA_UPDATER := true
BOARD_USES_RECOVERY_AS_BOOT := true
BOARD_BUILD_SYSTEM_ROOT_IMAGE := true
TARGET_NO_RECOVERY := true
AB_OTA_PARTITIONS := boot system vendor

# Match the extracted SD-X701F partition table to avoid oversized images.
BOARD_BOOTIMAGE_PARTITION_SIZE := 33554432
BOARD_SYSTEMIMAGE_PARTITION_SIZE := 536870912
BOARD_USERDATAIMAGE_PARTITION_SIZE := 1246486016
BOARD_FLASH_BLOCK_SIZE := 131072
TARGET_USERIMAGES_USE_EXT4 := true
TARGET_USERIMAGES_USE_F2FS := true

# Platform
TARGET_BOARD_PLATFORM := msm8953
TARGET_BOARD_PLATFORM_GPU := qcom-adreno506

# Platform version (requis par TWRP 8.1)
PLATFORM_VERSION := 8.1.0
PLATFORM_SECURITY_PATCH := 2018-09-01

# Recovery fstab
TARGET_RECOVERY_FSTAB := device/lenovo/blueberry/recovery.fstab

# Display - panel HX83100A 800x1280 portrait rotation 270
TW_THEME := portrait_hdpi
TARGET_RECOVERY_PIXEL_FORMAT := "RGBX_8888"
TW_ROTATION := 270
TW_BRIGHTNESS_PATH := "/sys/class/leds/lcd-backlight/brightness"
TW_MAX_BRIGHTNESS := 255
TW_DEFAULT_BRIGHTNESS := 128

# TWRP
TW_DEVICE_VERSION := 2
TW_INCLUDE_NTFS_3G := true
TW_INCLUDE_REPACKTOOLS := true
TARGET_USES_MKE2FS := true
TW_NO_LEGACY_PROPS := true
