#!/usr/bin/env bash
set -euo pipefail

JOBS=$(nproc)
SOURCE_DIR=/build/lineage16_source
SEED_DIR=/seed
MANIFEST_FILE=/seed/../blueberry_manifest_lineage16.xml

echo "[1/7] Init LineageOS 16.0 manifest..."
mkdir -p "$SOURCE_DIR"
cd "$SOURCE_DIR"

if [ ! -d ".repo" ]; then
    repo init \
        -u https://github.com/LineageOS/android.git \
        -b lineage-16.0 \
        --depth=1
fi

# Manifest local pour les projets blueberry-spécifiques
mkdir -p .repo/local_manifests
cp "$MANIFEST_FILE" .repo/local_manifests/blueberry_lineage16.xml

echo "[2/7] Repo sync ($JOBS jobs) — environ 30-60 min..."
repo sync -c -j"$JOBS" --force-sync --no-tags --no-clone-bundle

echo "[3/7] Staging device tree blueberry..."
mkdir -p device/lenovo/blueberry
rsync -a --delete --exclude='.git' "$SEED_DIR/device/lenovo/blueberry/" device/lenovo/blueberry/

echo "[4/7] Staging vendor tree blueberry..."
mkdir -p vendor/lenovo/blueberry
rsync -a --delete --exclude='.git' "$SEED_DIR/vendor/lenovo/blueberry/" vendor/lenovo/blueberry/

echo "[5/7] Fix Python 3 compat dans les build tools..."
find build/tools -name "*.py" -print0 2>/dev/null | xargs -0 -r sed -i \
    -e 's/\.iteritems()/.items()/g' \
    -e 's/\.itervalues()/.values()/g' \
    -e 's/\.iterkeys()/.keys()/g' || true

echo "[6/7] Build LineageOS 16 blueberry..."
export ALLOW_MISSING_DEPENDENCIES=true
export WITH_DEXPREOPT=false
source build/envsetup.sh
breakfast lineage_blueberry
mka -j"$JOBS" \
    bacon \
    2>&1 | tee /out/build-lineage16.log
BUILD_EXIT=${PIPESTATUS[0]}
echo "=== Build exit: $BUILD_EXIT ==="

echo "[7/7] Copie des artifacts..."
OUT_PRODUCT="out/target/product/blueberry"
for img in boot.img system.img vendor.img vbmeta.img; do
    if [ -f "$OUT_PRODUCT/$img" ]; then
        cp "$OUT_PRODUCT/$img" /out/ && echo "  $img OK"
    else
        echo "  $img NON TROUVÉ"
    fi
done

exit $BUILD_EXIT
