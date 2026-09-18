"""Tests for the verification-only flat CPU program image loader."""

from verification.cpu_program import load_intel_hex, write_readmemh


def _record(address: int, record_type: int, payload: bytes) -> str:
    body = bytes(
        [len(payload), address >> 8, address & 0xFF, record_type]
    ) + payload
    checksum = (-sum(body)) & 0xFF
    return ":" + (body + bytes([checksum])).hex().upper()


def test_intel_hex_flat_memory_round_trip(tmp_path) -> None:
    source = tmp_path / "program.hex"
    source.write_text(
        "\n".join(
            [
                _record(0x0400, 0x00, bytes([0xA9, 0x42, 0xEA])),
                _record(0xFFFC, 0x00, bytes([0x00, 0x04])),
                _record(0, 0x01, b""),
            ]
        )
        + "\n",
        encoding="ascii",
    )
    memory = load_intel_hex(source)
    assert len(memory) == 0x10000
    assert memory[0x0400:0x0403] == bytes([0xA9, 0x42, 0xEA])
    assert memory[0xFFFC:0xFFFE] == bytes([0x00, 0x04])

    readmemh = tmp_path / "program.mem"
    write_readmemh(memory, readmemh)
    lines = readmemh.read_text(encoding="ascii").splitlines()
    assert len(lines) == 0x10000
    assert lines[0x0400:0x0403] == ["a9", "42", "ea"]
