import struct
import zlib
from pathlib import Path
from uuid import UUID, uuid5

SECTOR_SIZE = 512
ENTRY_SIZE = 128
ENTRY_COUNT = 128
AB_FLAG_OFFSET = 6
AB_PARTITION_ATTR_SLOT_ACTIVE = 0x1 << 2

PROJECT_ROOT = Path(__file__).resolve().parents[1]
FIRST100 = PROJECT_ROOT / "logs" / "first100.bin"
LAST100 = PROJECT_ROOT / "logs" / "last100.bin"
PRIMARY_OUT = PROJECT_ROOT / "logs" / "gpt_primary_fixed.bin"
BACKUP_OUT = PROJECT_ROOT / "logs" / "gpt_backup_fixed.bin"

PARTITION_NAMES = {
    1: "persist",
    2: "modem_a",
    3: "modem_b",
    4: "drm_a",
    5: "drm_b",
    6: "bluetooth_a",
    7: "bluetooth_b",
    8: "rpm_a",
    9: "rpm_b",
    10: "aboot_a",
    11: "aboot_b",
    12: "sbl1_a",
    13: "sbl1_b",
    14: "tz_a",
    15: "tz_b",
    16: "devcfg_a",
    17: "devcfg_b",
    18: "modemst1",
    19: "modemst2",
    20: "misc",
    21: "fsc",
    22: "ssd",
    23: "DDR",
    24: "fsg",
    25: "sec",
    26: "boot_a",
    27: "boot_b",
    28: "system_a",
    29: "system_b",
    30: "vbmeta_a",
    31: "vbmeta_b",
    32: "vendor_a",
    33: "vendor_b",
    34: "oem_bootloader_a",
    35: "oem_bootloader_b",
    36: "factory",
    37: "factory_bootloader",
    38: "devinfo",
    39: "keystore",
    40: "config",
    41: "cmnlib_a",
    42: "cmnlib_b",
    43: "dsp_a",
    44: "dsp_b",
    45: "limits",
    46: "dip",
    47: "syscfg",
    48: "mcfg",
    49: "keymaster_a",
    50: "keymaster_b",
    51: "apdp",
    52: "msadp",
    53: "dpo",
    54: "oem_a",
    55: "oem_b",
    56: "userdata",
}

GUIDS = {
    "persist": "6c95e238-e343-4ba8-b489-8681ed22ad0b",
    "userdata": "0bb7e6ed-4424-49c0-9372-7fbab465ab4c",
    "misc": "6b2378b0-0fbc-4aa9-a4f6-4d6e17281c47",
    "boot": "bb499290-b57e-49f6-bf41-190386693794",
    "bootloader": "4892aeb3-a45f-4c5f-875f-da3303c0795c",
    "system": "0f2778c4-5cc1-4300-8670-6c88b7e57ed6",
    "oem": "aa3434b2-ddc3-4065-8b1a-18e99ea15cb7",
    "vbmeta": "b598858a-5fe3-418e-b8c4-824b41f4adfc",
    "vendor_specific": "314f99d5-b2bf-4883-8d03-e2f2ce507d6a",
    "modemst1": "ebbeadaf-22c9-e33b-8f5d-0e81686a68cb",
    "modemst2": "0a288b1f-22c9-e33b-8f5d-0e81686a68cb",
    "fsc": "57b90a16-22c9-e33b-8f5d-0e81686a68cb",
    "fsg": "638ff8e2-22c9-e33b-8f5d-0e81686a68cb",
    "ssd": "2c86e742-745e-4fdd-bfd8-b6a7ac638772",
    "keystore": "de7d4029-0f5b-41c8-ae7e-f6c023a02b33",
}
UUID_NAMESPACE = UUID("b4e38c2a-6c84-4d23-b2b6-5ab72a6917f7")


def slot_flags(name: str, current_flags: int) -> int:
    if name == "boot_a":
        return 0x6F << (AB_FLAG_OFFSET * 8)
    if name == "boot_b":
        return 0x3A << (AB_FLAG_OFFSET * 8)
    if name.endswith("_a"):
        return current_flags | (AB_PARTITION_ATTR_SLOT_ACTIVE << (AB_FLAG_OFFSET * 8))
    if name.endswith("_b"):
        return current_flags & ~(AB_PARTITION_ATTR_SLOT_ACTIVE << (AB_FLAG_OFFSET * 8))
    return current_flags


def guid_to_gpt_bytes(guid_text: str) -> bytes:
    guid = UUID(guid_text)
    return (
        guid.time_low.to_bytes(4, "little") +
        guid.time_mid.to_bytes(2, "little") +
        guid.time_hi_version.to_bytes(2, "little") +
        guid.bytes[8:]
    )


def partition_type_guid(name: str) -> bytes:
    if name == "persist":
        return guid_to_gpt_bytes(GUIDS["persist"])
    if name == "userdata":
        return guid_to_gpt_bytes(GUIDS["userdata"])
    if name == "misc":
        return guid_to_gpt_bytes(GUIDS["misc"])
    if name in {"modemst1", "modemst2", "fsc", "fsg", "ssd", "keystore"}:
        return guid_to_gpt_bytes(GUIDS[name])
    if name.startswith("boot_"):
        return guid_to_gpt_bytes(GUIDS["boot"])
    if name.startswith("vbmeta_"):
        return guid_to_gpt_bytes(GUIDS["vbmeta"])
    if name.startswith("system_"):
        return guid_to_gpt_bytes(GUIDS["system"])
    if name.startswith("oem_bootloader_"):
        return guid_to_gpt_bytes(GUIDS["bootloader"])
    if name.startswith("oem_"):
        return guid_to_gpt_bytes(GUIDS["oem"])
    if name.endswith("_a") or name.endswith("_b"):
        if any(prefix in name for prefix in ("aboot", "sbl1", "rpm", "tz", "devcfg", "cmnlib", "keymaster")):
            return guid_to_gpt_bytes(GUIDS["bootloader"])
        return guid_to_gpt_bytes(GUIDS["vendor_specific"])
    if name in {"factory_bootloader", "DDR"}:
        return guid_to_gpt_bytes(GUIDS["bootloader"])
    return guid_to_gpt_bytes(GUIDS["vendor_specific"])


def patch_entries(entry_blob: bytearray) -> bytearray:
    for index, name in PARTITION_NAMES.items():
        off = (index - 1) * ENTRY_SIZE
        entry = bytearray(entry_blob[off:off + ENTRY_SIZE])
        current_flags = struct.unpack_from("<Q", entry, 48)[0]
        if entry[0:16] == b"\x00" * 16:
            entry[0:16] = partition_type_guid(name)
        if entry[16:32] == b"\x00" * 16:
            entry[16:32] = guid_to_gpt_bytes(str(uuid5(UUID_NAMESPACE, name)))
        struct.pack_into("<Q", entry, 48, slot_flags(name, current_flags))
        encoded = name.encode("utf-16le")
        entry[56:56 + 72] = b"\x00" * 72
        entry[56:56 + len(encoded)] = encoded
        entry_blob[off:off + ENTRY_SIZE] = entry
    return entry_blob


def patch_header(image: bytearray, header_offset: int, entries_offset: int) -> None:
    header_size = struct.unpack_from("<I", image, header_offset + 12)[0]
    entry_count = struct.unpack_from("<I", image, header_offset + 80)[0]
    entry_size = struct.unpack_from("<I", image, header_offset + 84)[0]
    entries_size = entry_count * entry_size
    entries = image[entries_offset:entries_offset + entries_size]
    entries_crc = zlib.crc32(entries) & 0xFFFFFFFF
    struct.pack_into("<I", image, header_offset + 88, entries_crc)
    struct.pack_into("<I", image, header_offset + 16, 0)
    header = bytes(image[header_offset:header_offset + header_size])
    header_crc = zlib.crc32(header) & 0xFFFFFFFF
    struct.pack_into("<I", image, header_offset + 16, header_crc)


def main() -> int:
    if not FIRST100.exists() or not LAST100.exists():
        raise SystemExit("Missing first100.bin or last100.bin in logs.")

    first = bytearray(FIRST100.read_bytes())
    last = bytearray(LAST100.read_bytes())

    primary_entries_offset = 2 * SECTOR_SIZE
    backup_entries_offset = 67 * SECTOR_SIZE
    backup_header_offset = 99 * SECTOR_SIZE

    primary_entries = patch_entries(bytearray(first[primary_entries_offset:primary_entries_offset + (ENTRY_COUNT * ENTRY_SIZE)]))
    backup_entries = patch_entries(bytearray(last[backup_entries_offset:backup_entries_offset + (ENTRY_COUNT * ENTRY_SIZE)]))

    first[primary_entries_offset:primary_entries_offset + len(primary_entries)] = primary_entries
    last[backup_entries_offset:backup_entries_offset + len(backup_entries)] = backup_entries

    patch_header(first, SECTOR_SIZE, primary_entries_offset)
    patch_header(last, backup_header_offset, backup_entries_offset)

    PRIMARY_OUT.write_bytes(first[:34 * SECTOR_SIZE])
    BACKUP_OUT.write_bytes(last[backup_entries_offset:])

    print(f"Wrote {PRIMARY_OUT}")
    print(f"Wrote {BACKUP_OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
