import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
TOOLS_ROOT = PROJECT_ROOT / "tools" / "edl"
LOADER = Path(r"C:\Users\Matthieu MAUREL\Downloads\amber_blueberry_firehose\amber_bluebbery_prog_emmc_firehose_8953_ddr.mbn")

sys.path.insert(0, str(TOOLS_ROOT))
_original_argv = sys.argv[:]
sys.argv = [sys.argv[0]]
try:
    from edl import main as Edl  # noqa: E402
finally:
    sys.argv = _original_argv


EDL_ARGS = {
    "--debugmode": False,
    "--devicemodel": None,
    "--genxml": False,
    "--gpt-num-part-entries": "0",
    "--gpt-part-entry-size": "0",
    "--gpt-part-entry-start-lba": "0",
    "--loader": str(LOADER),
    "--lun": None,
    "--maxpayload": "0x100000",
    "--memory": "emmc",
    "--pagesperblock": "0",
    "--partitionfilename": None,
    "--partitions": None,
    "--pid": "0x9008",
    "--portname": None,
    "--resetmode": "reset",
    "--sectorsize": None,
    "--serial": False,
    "--serial_number": None,
    "--skip": None,
    "--skipresponse": False,
    "--skipstorageinit": False,
    "--skipwrite": False,
    "--tcpport": "1340",
    "--vid": "0x05c6",
    "<command>": None,
    "<data>": None,
    "<directory>": None,
    "<filename>": None,
    "<imagedir>": None,
    "<length>": None,
    "<lun>": None,
    "<offset>": None,
    "<options>": None,
    "<partitionname>": None,
    "<patch>": None,
    "<rawprogram>": None,
    "<sectors>": None,
    "<size>": None,
    "<slot>": None,
    "<start_sector>": None,
    "<xmlfile>": None,
    "<xmlstring>": None,
}


def main() -> int:
    slot = "a"
    if len(sys.argv) > 1:
        if sys.argv[1] not in {"a", "b"}:
            print("usage: edl-firehose-slot-reset.py [a|b]", file=sys.stderr)
            return 2
        slot = sys.argv[1]

    args = dict(EDL_ARGS)
    client = Edl(args)
    status = client.run()
    print(f"init_status={status}")
    if status != 0:
        return status

    try:
        client.fh.cfg.SECTOR_SIZE_IN_BYTES = 512
        client.args["<slot>"] = slot
        slot_res = client.fh.handle_firehose("setactiveslot", client.args)
        print(f"setactiveslot_{slot}_result={slot_res}")
        reset_res = client.fh.handle_firehose("reset", client.args)
        print(f"reset_result={reset_res}")
        return 0 if reset_res else 1
    finally:
        client.exit(cdc_close=True)


if __name__ == "__main__":
    raise SystemExit(main())
