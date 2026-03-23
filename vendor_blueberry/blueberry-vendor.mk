# Vendor blobs for blueberry (Lenovo Smart Display 10) — identical hardware to starfire
#
# Dedicated blueberry vendor entrypoint.
#
# The long-term target is a native blob tree under:
#   vendor/lenovo/blueberry/proprietary/blueberry-vendor-blobs.mk
#
# Until extraction is complete, keep the starfire fallback explicit so the
# dependency remains visible during bring-up.
#

BLUEBERRY_VENDOR_BLOBS := vendor/lenovo/blueberry/proprietary/blueberry-vendor-blobs.mk
STARFIRE_VENDOR_FALLBACK := vendor/lenovo/starfire/starfire-vendor.mk

ifneq ($(wildcard $(BLUEBERRY_VENDOR_BLOBS)),)
$(call inherit-product, $(BLUEBERRY_VENDOR_BLOBS))
else
$(warning blueberry vendor blobs missing; falling back explicitly to $(STARFIRE_VENDOR_FALLBACK))
$(call inherit-product, $(STARFIRE_VENDOR_FALLBACK))
endif
