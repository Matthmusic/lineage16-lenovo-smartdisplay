# Rapport Hardware — Lenovo Smart Display 10" (SD-X701F)

## Panel d'affichage

| Clé | Valeur |
|-----|--------|
| Nom du panel | `hx83100a 800p video mode dsi panel` |
| Contrôleur | Himax HX83100A (DSI Video Mode) |
| Résolution physique | 800 × 1280 px |
| Orientation physique | Portrait (270° de rotation logicielle) |
| DPI | 240 |
| Backlight | `lcd-backlight` via WLED (max 255) |

## Pilote tactile

| Clé | Valeur |
|-----|--------|
| Nom kernel | `himax-touchscreen` |
| Interface | I2C |
| Pilote | `CONFIG_TOUCHSCREEN_HIMAX_CHIPSET=y` + `CONFIG_TOUCHSCREEN_HIMAX_I2C=y` |
| Note | Même fabricant que le panel (Himax Semiconductors) |

## Device Tree Blob actif

| Clé | Valeur |
|-----|--------|
| Modèle DTB | `Qualcomm Technologies, Inc. APQ8053 Lite DragonBoard V2.1` |
| msm-id | `0x00000130` = 304 = APQ8053 |
| board-id | `0x01010020 0x00000000` |
| Fichier extrait | `extracted_dtb_25.dtb` (261 KB) |
| Total DTBs dans le kernel | 51 |

## Kernel

| Clé | Valeur |
|-----|--------|
| Source kernel | Android Things (APQ8053/MSM8953 custom) |
| Configs display | `CONFIG_FB_MSM=y`, `CONFIG_FB_MSM_MDSS=y` |
| Configs touch | `CONFIG_TOUCHSCREEN_HIMAX_CHIPSET=y`, `CONFIG_TOUCHSCREEN_HIMAX_I2C=y` |
| Config.gz | 4966 lignes, extrait dans `kernel_config.txt` |

## WiFi / Bluetooth

| Clé | Valeur |
|-----|--------|
| WiFi driver | QCA_CLD |
| WiFi firmware | `WCNSS_cfg.dat` + `WCNSS_qcom_cfg.ini` |
| BT SOC | `qcom.bluetooth.soc=naples_uart` |

## Audio

| Clé | Valeur |
|-----|--------|
| Sound card | `msm8953-openq624-snd-card` |

## Propriétés système clés

```
ro.sf.lcd_density=240
ro.display.defaultrotation=270
ro.display.reverserotation=true
ro.oem.product.model=Lenovo Smart Display 10
```

## Fstab (partitions montées)

| Partition | Point de montage | Type | Flags |
|-----------|-----------------|------|-------|
| system | / | ext4 | A/B slot, AVB |
| userdata | /data | ext4 | encryptable |
| modem | /firmware | ext4 | A/B slot, AVB |
| drm | /drm_fw | ext4 | A/B slot |
| bluetooth | /bt_firmware | ext4 | A/B slot, AVB |
| persist | /persist | ext4 | |
| dsp | /dsp | ext4 | A/B slot, AVB |
| oem | /oem | ext4 | A/B slot |
| vbmeta | /vbmeta | emmc | A/B slot |

---

## Delta avec le device tree starfire (ThinkSmart View)

| Paramètre | Smart Display 10" (NOTRE APPAREIL) | ThinkSmart View (starfire) |
|-----------|-----------------------------------|-----------------------------|
| DPI | **240** | 260 |
| Rotation | **270°** (`ro.display.defaultrotation=270`) | Pas de rotation |
| Panel | **hx83100a** | Inconnu (différent) |
| Touch | **himax-touchscreen (I2C)** | Inconnu |
| DTB modèle | APQ8053 Lite DragonBoard **V2.1** | À confirmer |
| Audio | **msm8953-openq624** | Même (openq624 aussi) |

### Modifications nécessaires dans le device tree starfire pour notre appareil :

1. `vendor_prop.mk` : changer `ro.sf.lcd_density=260` → `240`
2. `vendor_prop.mk` : ajouter `ro.display.defaultrotation=270`
3. `vendor_prop.mk` : ajouter `ro.display.reverserotation=true`
4. Vérifier que le kernel starfire a `CONFIG_TOUCHSCREEN_HIMAX_CHIPSET=y`
   (sinon ajouter au defconfig)
5. Vérifier que le DTB du kernel starfire inclut le panel hx83100a
   (sinon le copier depuis notre kernel)

### Bonne nouvelle :
Le kernel `android_kernel_lenovo_apq8053` est partagé entre les deux appareils
(TSV et Smart Display partagent la base APQ8053). Le Himax driver est probablement
déjà présent ou facilement activable.
