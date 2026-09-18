"""Verification-only flat-memory CPU program image helpers."""

from pathlib import Path


def load_intel_hex(path: str | Path) -> bytearray:
    """Load an Intel HEX image into deterministic flat 64 KiB memory."""

    memory = bytearray(0x10000)
    upper_address = 0
    saw_eof = False
    for line_number, raw_line in enumerate(
        Path(path).read_text(encoding="ascii").splitlines(), start=1
    ):
        line = raw_line.strip()
        if not line:
            continue
        if not line.startswith(":"):
            raise ValueError(f"Intel HEX line {line_number} lacks ':'")
        record = bytes.fromhex(line[1:])
        if len(record) < 5 or len(record) != record[0] + 5:
            raise ValueError(f"Intel HEX line {line_number} has invalid length")
        if sum(record) & 0xFF:
            raise ValueError(f"Intel HEX line {line_number} has invalid checksum")
        count = record[0]
        address = (record[1] << 8) | record[2]
        record_type = record[3]
        payload = record[4 : 4 + count]
        if record_type == 0x00:
            absolute = upper_address + address
            if absolute + count > len(memory):
                raise ValueError("image exceeds flat 64 KiB CPU memory")
            memory[absolute : absolute + count] = payload
        elif record_type == 0x01:
            saw_eof = True
            break
        elif record_type == 0x04:
            if count != 2:
                raise ValueError("invalid extended-linear-address record")
            upper_address = ((payload[0] << 8) | payload[1]) << 16
        else:
            raise ValueError(f"unsupported Intel HEX record type {record_type:02X}")
    if not saw_eof:
        raise ValueError("Intel HEX image has no EOF record")
    return memory


def write_readmemh(memory: bytes | bytearray, path: str | Path) -> None:
    """Write one byte per line for SystemVerilog ``$readmemh``."""

    if len(memory) != 0x10000:
        raise ValueError("flat CPU memory image must contain exactly 65536 bytes")
    Path(path).write_text(
        "".join(f"{value:02x}\n" for value in memory), encoding="ascii"
    )
