$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base_telephony.mk)

# Vendor blobs (fallback starfire si pas encore extrait)
$(call inherit-product, vendor/lenovo/blueberry/blueberry-vendor.mk)

# Overlays
DEVICE_PACKAGE_OVERLAYS += device/lenovo/blueberry/overlay

# Propriétés de l'appareil
$(call inherit-product, device/lenovo/blueberry/device.mk)

# Identité produit
PRODUCT_DEVICE     := blueberry
PRODUCT_NAME       := lineage_blueberry
PRODUCT_BRAND      := Lenovo
PRODUCT_MODEL      := Lenovo Smart Display 10
PRODUCT_MANUFACTURER := Lenovo

PRODUCT_GMS_CLIENTID_BASE := android-lenovo

TARGET_VENDOR := lenovo

PRODUCT_BUILD_PROP_OVERRIDES += \
    PRIVATE_BUILD_DESC="blueberry-user 8.1.0 OPM1.171019.019 test-keys" \
    BUILD_FINGERPRINT="Lenovo/blueberry/blueberry:8.1.0/OPM1.171019.019/test-keys:user/release-keys"
