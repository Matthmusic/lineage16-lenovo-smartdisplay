LOCAL_PATH := device/lenovo/blueberry

# Architecture
TARGET_ARCH := arm
TARGET_ARCH_VARIANT := armv7-a-neon
TARGET_CPU_ABI := armeabi-v7a
TARGET_CPU_ABI2 := armeabi
TARGET_CPU_VARIANT := cortex-a53
TARGET_2ND_ARCH :=
TARGET_USES_64_BIT_BINDER := false

# Bootloader
TARGET_BOOTLOADER_BOARD_NAME := msm8953
TARGET_NO_BOOTLOADER := true

# Kernel (prebuilt extrait du stock Android Things)
TARGET_PREBUILT_KERNEL := device/lenovo/blueberry/prebuilt/zImage
BOARD_KERNEL_CMDLINE := console=ttyMSM0,115200,n8 earlyprintk androidboot.hardware=msm8x53 androidboot.bootdevice=7824900.sdhci firmware_class.path=/oem/firmware androidboot.selinux=permissive
BOARD_KERNEL_BASE        := 0x10000000
BOARD_KERNEL_PAGESIZE    := 2048
BOARD_KERNEL_TAGS_OFFSET := 0x00000100
BOARD_RAMDISK_OFFSET     := 0x01000000
BOARD_MKBOOTIMG_ARGS     := --ramdisk_offset 0x01000000 --tags_offset 0x00000100

# Platform
TARGET_BOARD_PLATFORM     := msm8953
TARGET_BOARD_PLATFORM_GPU := qcom-adreno506

# A/B (no dedicated recovery partition)
AB_OTA_UPDATER              := true
BOARD_USES_RECOVERY_AS_BOOT := true
BOARD_BUILD_SYSTEM_ROOT_IMAGE := true
TARGET_NO_RECOVERY          := true
AB_OTA_PARTITIONS           := boot system vendor

# Partitions (tailles extraites de la table GPT de la SD-X701F)
BOARD_BOOTIMAGE_PARTITION_SIZE   := 33554432
BOARD_SYSTEMIMAGE_PARTITION_SIZE := 536870912
BOARD_VENDORIMAGE_PARTITION_SIZE := 134217728
BOARD_USERDATAIMAGE_PARTITION_SIZE := 1246486016
BOARD_FLASH_BLOCK_SIZE           := 131072

# Filesystems
TARGET_USERIMAGES_USE_EXT4 := true
TARGET_USERIMAGES_USE_F2FS := true
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE := ext4
TARGET_COPY_OUT_VENDOR := vendor

# Treble
BOARD_PROPERTY_OVERRIDES_SPLIT_ENABLED := true
PRODUCT_FULL_TREBLE_OVERRIDE := true

# SELinux - permissive pendant le porting
BOARD_KERNEL_CMDLINE += androidboot.selinux=permissive
BOARD_SEPOLICY_DIRS += device/lenovo/blueberry/sepolicy

# Display
TARGET_SCREEN_DENSITY := 240

# HIDL
DEVICE_MANIFEST_FILE := device/lenovo/blueberry/manifest.xml

# Qualcomm support
BOARD_USES_QCOM_HARDWARE := true

# Security patch (stock baseline)
PLATFORM_SECURITY_PATCH := 2018-09-01
PLATFORM_VERSION         := 9

# fstab
TARGET_RECOVERY_FSTAB := device/lenovo/blueberry/rootdir/etc/fstab.msm8x53
