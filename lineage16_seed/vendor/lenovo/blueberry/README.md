# Blueberry Vendor Staging

This directory is the explicit vendor staging point for the Android 9 / LineageOS 16 bring-up.

Rules:

- `blueberry-vendor.mk` and `BoardConfigVendor.mk` prefer native `blueberry` blobs.
- If the native blob tree is not extracted yet, the fallback to `starfire` is explicit and emits a build warning.
- The fallback is temporary. The goal is a dedicated `vendor/lenovo/blueberry/proprietary` payload sourced from:
  - the exact Blueberry factory package used during recovery
  - then the live device if a blob is missing or differs
- Do not reintroduce silent delegation.
