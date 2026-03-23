# Dedicated blueberry vendor board config entrypoint.
#
# A native blueberry blob tree will eventually live under:
#   vendor/lenovo/blueberry/proprietary/BoardConfigVendor.mk
#
# Until extraction is complete, fall back explicitly to starfire so the
# bring-up path is obvious and grep-friendly.

BLUEBERRY_VENDOR_BOARD_CONFIG := vendor/lenovo/blueberry/proprietary/BoardConfigVendor.mk
STARFIRE_VENDOR_BOARD_CONFIG := vendor/lenovo/starfire/BoardConfigVendor.mk

ifneq ($(wildcard $(BLUEBERRY_VENDOR_BOARD_CONFIG)),)
include $(BLUEBERRY_VENDOR_BOARD_CONFIG)
else
$(warning blueberry vendor board config missing; falling back explicitly to $(STARFIRE_VENDOR_BOARD_CONFIG))
include $(STARFIRE_VENDOR_BOARD_CONFIG)
endif
