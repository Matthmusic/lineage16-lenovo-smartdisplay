#!/usr/bin/env bash
set -euo pipefail

JOBS=$(nproc)
SOURCE_DIR=/build/twrp_source
DEVICE_TREE=/device_tree

echo "[1/6] Init TWRP 8.1 manifest..."
mkdir -p "$SOURCE_DIR"
cd "$SOURCE_DIR"

if [ ! -d ".repo" ]; then
    repo init \
        -u https://github.com/minimal-manifest-twrp/platform_manifest_twrp_omni.git \
        -b twrp-8.1 --depth=1
fi

echo "[2/6] Repo sync ($JOBS jobs)..."
repo sync -c -j"$JOBS" --force-sync --no-tags --no-clone-bundle

echo "[3/6] Fix Python 2 build scripts..."
NOOP='#!/usr/bin/env python3\nimport sys\nsys.exit(0)\n'
for f in vendor/omni/build/tools/roomservice.py build/tools/check_radio_versions.py; do
    [ -f "$f" ] && printf "$NOOP" > "$f" && echo "  disabled: $f"
done

find build/tools -name "*.py" -print0 | xargs -0 -r sed -i \
    -e 's/\.iteritems()/.items()/g' \
    -e 's/\.itervalues()/.values()/g' \
    -e 's/\.iterkeys()/.keys()/g'
echo "  Python 3 patches applied"

echo "[4/6] Copy device tree..."
mkdir -p device/lenovo/blueberry
rsync -a --exclude='.git' --exclude='.github' "$DEVICE_TREE/" device/lenovo/blueberry/

echo "[5/6] Build TWRP..."
export ALLOW_MISSING_DEPENDENCIES=true
source build/envsetup.sh
lunch omni_blueberry-eng
mka -j"$JOBS" bootimage 2>&1 | tee /out/build.log
echo "Build exit: ${PIPESTATUS[0]}"

echo "[6/6] Copy artifacts..."
cp out/target/product/blueberry/boot.img /out/ 2>/dev/null && echo "  boot.img OK" || echo "  boot.img NOT FOUND"
cp out/target/product/blueberry/recovery.img /out/ 2>/dev/null && echo "  recovery.img OK" || true

echo "=== DONE ==="
