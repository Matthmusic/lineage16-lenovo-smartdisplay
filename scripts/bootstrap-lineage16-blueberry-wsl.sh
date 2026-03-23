#!/usr/bin/env bash
set -euo pipefail

BUILD_ROOT="$1"
MANIFEST="$2"
SEED_ROOT="$3"
JOBS="$4"
SKIP_SYNC="$5"
DEVICE_SEED="$SEED_ROOT/device/lenovo/blueberry"
VENDOR_SEED="$SEED_ROOT/vendor/lenovo/blueberry"

if ! command -v repo >/dev/null 2>&1; then
  echo "[bootstrap] repo command not found in WSL. Run install-lineage16-wsl-prereqs.ps1 first." >&2
  exit 1
fi

echo "[bootstrap] build root: $BUILD_ROOT"
mkdir -p "$BUILD_ROOT"
cd "$BUILD_ROOT"

if [ ! -d ".repo" ]; then
  echo "[bootstrap] repo init lineage-16.0"
  repo init -u https://github.com/LineageOS/android.git -b lineage-16.0
fi

mkdir -p .repo/local_manifests
cp "$MANIFEST" .repo/local_manifests/blueberry_lineage16.xml

if [ "$SKIP_SYNC" != "1" ]; then
  echo "[bootstrap] repo sync start"
  repo sync -c -j"$JOBS" --force-sync
  echo "[bootstrap] repo sync done"
fi

echo "[bootstrap] staging blueberry seed"
mkdir -p device/lenovo/blueberry vendor/lenovo/blueberry
rm -rf device/lenovo/blueberry vendor/lenovo/blueberry
mkdir -p device/lenovo/blueberry vendor/lenovo/blueberry

tar --exclude='.git' -cf - -C "$DEVICE_SEED" . | tar -xf - -C device/lenovo/blueberry
tar --exclude='.git' -cf - -C "$VENDOR_SEED" . | tar -xf - -C vendor/lenovo/blueberry

echo "[bootstrap] Lineage 16 blueberry tree prepared at $BUILD_ROOT"
