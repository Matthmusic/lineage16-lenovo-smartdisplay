#!/usr/bin/env bash
# Flash LineageOS 16 sur le slot B du Lenovo Smart Display (blueberry)
# Usage: ./flash-slot-b.sh [dossier_out]
set -euo pipefail

FASTBOOT="${FASTBOOT:-/home/serveurdev/Android/Sdk/platform-tools/fastboot}"
OUT_DIR="${1:-/home/serveurdev/lineage16-lenovo-smartdisplay/out}"

check_device() {
    local dev
    dev=$("$FASTBOOT" devices 2>/dev/null | awk '{print $1}')
    if [ -z "$dev" ]; then
        echo "ERREUR: aucun device en fastboot. Vérifiez la connexion USB."
        exit 1
    fi
    echo "Device détecté: $dev"
}

flash_partition() {
    local part="$1"
    local img="$OUT_DIR/$2"
    if [ ! -f "$img" ]; then
        echo "  SKIP $part — $img absent"
        return
    fi
    echo "  Flash $part → $img"
    "$FASTBOOT" flash "$part" "$img"
}

echo "=== Flash LineageOS 16 → slot B ==="
check_device

echo "--- Vérification slot actif ---"
"$FASTBOOT" getvar current-slot 2>&1 || true

echo "--- Flash partitions slot B ---"
flash_partition boot_b   boot.img
flash_partition system_b system.img
flash_partition vendor_b vendor.img
flash_partition vbmeta_b vbmeta.img

echo "--- Activation slot B ---"
"$FASTBOOT" set_active b

echo "--- Reboot ---"
"$FASTBOOT" reboot

echo "=== Flash terminé. Le device redémarre sur slot B (LineageOS 16). ==="
echo "En cas d'échec de boot, rollback slot A:"
echo "  $FASTBOOT set_active a && $FASTBOOT reboot"
