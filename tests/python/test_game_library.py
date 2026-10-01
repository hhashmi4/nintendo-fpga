from __future__ import annotations

from io import StringIO
import os
from pathlib import Path
import unicodedata

import pytest

import software.nes_loader.cli as loader_cli
import software.nes_loader.library as library_module
from software.nes_loader.cli import run
from software.nes_loader.library import (
    GameLibrary,
    GameNotLoadableError,
    LibraryNotFoundError,
    LibraryUnavailableError,
    UnsafeGameSelection,
)
from software.nes_loader.loader import LoadPlan, execute_load_plan
from software.nes_loader.protocol import PRG_NROM128_BYTES
from software.nes_loader.transport import MockRuntimeLoaderTransport
from verification.runtime_loader_fixtures import (
    make_ines,
    write_game_library,
)


def test_missing_and_empty_libraries_are_distinct(tmp_path: Path):
    missing = tmp_path / "not-mounted"
    with pytest.raises(LibraryNotFoundError, match="not mounted or not found"):
        GameLibrary(missing).scan()

    empty = tmp_path / "empty"
    empty.mkdir()
    assert GameLibrary(empty).scan() == ()

    stdout = StringIO()
    assert run(["list", "--library", str(empty)], stdout=stdout, stderr=StringIO()) == 0
    assert "No .nes games found" in stdout.getvalue()

    stderr = StringIO()
    assert (
        run(["list", "--library", str(missing)], stdout=StringIO(), stderr=stderr)
        == 2
    )
    assert "not mounted or not found" in stderr.getvalue()


def test_mixed_generated_library_classifies_every_rom(tmp_path: Path):
    paths = write_game_library(tmp_path / "games")
    entries = GameLibrary(tmp_path / "games").scan()
    by_id = {entry.game_id: entry for entry in entries}

    assert len(entries) == 8
    assert "notes.txt" not in by_id
    assert by_id["Alpha Test.nes"].supported
    assert by_id["Beta CHR-RAM.NES"].supported
    assert by_id["Beta CHR-RAM.NES"].nrom_mode == "NROM-256"
    assert by_id["Beta CHR-RAM.NES"].chr_type.value == "RAM"
    assert by_id["Unsupported Mapper 2.nes"].valid
    assert not by_id["Unsupported Mapper 2.nes"].supported
    assert "Mapper 2" in by_id["Unsupported Mapper 2.nes"].reason
    assert not by_id["Corrupt Header.nes"].valid
    assert "magic" in by_id["Corrupt Header.nes"].reason
    assert not by_id["Truncated Payload.nes"].valid
    assert "truncated" in by_id["Truncated Payload.nes"].reason
    assert all(path.exists() for path in paths.values())


def test_sorting_is_deterministic_and_locale_independent(tmp_path: Path):
    root = tmp_path / "games"
    root.mkdir()
    payload = make_ines()
    names = ["zeta.nes", "Alpha.nes", "alpha.NES", "Éclair.nes", "星.nes"]
    for name in reversed(names):
        (root / name).write_bytes(payload)

    expected = sorted(
        names,
        key=lambda name: (
            unicodedata.normalize("NFC", name).casefold(),
            unicodedata.normalize("NFC", name),
            name,
        ),
    )
    first = [entry.game_id for entry in GameLibrary(root).scan()]
    second = [entry.game_id for entry in GameLibrary(root).scan()]
    assert first == expected == second


def test_non_recursive_scan_ignores_directories_symlinks_and_special_files(
    tmp_path: Path,
):
    root = tmp_path / "games"
    root.mkdir()
    (root / "real.nes").write_bytes(make_ines())
    nested = root / "nested"
    nested.mkdir()
    (nested / "hidden.nes").write_bytes(make_ines())
    (root / "directory.nes").mkdir()
    (root / "readme.txt").write_text("not a ROM", encoding="utf-8")
    os.mkfifo(root / "pipe.nes")
    outside = tmp_path / "outside.nes"
    outside.write_bytes(make_ines())
    (root / "linked.nes").symlink_to(outside)

    assert [entry.game_id for entry in GameLibrary(root).scan()] == ["real.nes"]


def test_spaces_unicode_long_names_and_case_insensitive_extension(tmp_path: Path):
    root = tmp_path / "games"
    root.mkdir()
    names = [
        "Game With Spaces.nes",
        "試験ゲーム.NeS",
        f"{'long-name-' * 18}.NES",
    ]
    for name in names:
        (root / name).write_bytes(make_ines())

    entries = GameLibrary(root).scan()
    assert {entry.game_id for entry in entries} == set(names)
    assert all(entry.supported for entry in entries)


def test_duplicate_display_names_keep_distinct_stable_ids(tmp_path: Path):
    root = tmp_path / "games"
    write_game_library(root)
    library = GameLibrary(root)
    duplicates = [
        entry for entry in library.scan() if entry.display_name == "Duplicate"
    ]
    assert {entry.game_id for entry in duplicates} == {
        "Duplicate.nes",
        "Duplicate.NES",
    }
    assert library.select("Duplicate.nes").game_id == "Duplicate.nes"
    assert library.select("Duplicate.NES").game_id == "Duplicate.NES"


@pytest.mark.parametrize(
    "game_id",
    ["", "../outside.nes", "nested/game.nes", "/tmp/outside.nes", ".", ".."],
)
def test_selection_rejects_traversal_absolute_and_nested_paths(
    tmp_path: Path, game_id: str
):
    root = tmp_path / "games"
    root.mkdir()
    with pytest.raises(UnsafeGameSelection):
        GameLibrary(root).select(game_id)


def test_symlinked_game_is_excluded_and_cannot_be_selected(tmp_path: Path):
    root = tmp_path / "games"
    root.mkdir()
    outside = tmp_path / "outside.nes"
    outside.write_bytes(make_ines())
    (root / "escape.nes").symlink_to(outside)
    library = GameLibrary(root)
    assert library.scan() == ()
    with pytest.raises(UnsafeGameSelection, match="symlinked"):
        library.select("escape.nes")


def test_read_only_library_scans_and_loads_without_writes(tmp_path: Path):
    root = tmp_path / "games"
    root.mkdir()
    path = root / "read-only.nes"
    payload = make_ines(chr_banks=0)
    path.write_bytes(payload)
    path.chmod(0o444)
    root.chmod(0o555)
    try:
        entry, image = GameLibrary(root).load("read-only.nes")
        assert entry.supported
        assert image.prg_size == PRG_NROM128_BYTES
        assert path.read_bytes() == payload
    finally:
        root.chmod(0o755)
        path.chmod(0o644)


def test_per_file_permission_error_does_not_abort_scan(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
):
    root = tmp_path / "games"
    root.mkdir()
    (root / "good.nes").write_bytes(make_ines())
    (root / "locked.nes").write_bytes(make_ines())
    original = library_module.inspect_ines_file

    def inspect(path: Path):
        if path.name == "locked.nes":
            raise PermissionError(13, "Permission denied", str(path))
        return original(path)

    monkeypatch.setattr(library_module, "inspect_ines_file", inspect)
    by_id = {entry.game_id: entry for entry in GameLibrary(root).scan()}
    assert by_id["good.nes"].supported
    assert not by_id["locked.nes"].valid
    assert "Permission denied" in by_id["locked.nes"].reason


@pytest.mark.parametrize(
    ("name", "payload", "reason"),
    [
        ("bad-magic.nes", b"BAD!" + bytes(12), "magic"),
        ("short-header.nes", b"NES\x1a", "16-byte"),
        ("short-payload.nes", make_ines()[:-1], "truncated"),
        ("trailing.nes", make_ines(trailing=b"x"), "trailing"),
        ("nes2.nes", make_ines(flags7=0x08), "NES 2.0"),
    ],
)
def test_corrupt_and_unsupported_formats_are_isolated(
    tmp_path: Path, name: str, payload: bytes, reason: str
):
    root = tmp_path / "games"
    root.mkdir()
    (root / "good.nes").write_bytes(make_ines())
    (root / name).write_bytes(payload)
    by_id = {entry.game_id: entry for entry in GameLibrary(root).scan()}
    assert by_id["good.nes"].supported
    assert not by_id[name].supported
    assert reason in by_id[name].reason


def test_large_library_uses_header_inspection_not_path_read_bytes(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
):
    root = tmp_path / "games"
    root.mkdir()
    payload = make_ines(chr_banks=0)
    for index in range(256):
        (root / f"generated-{index:03d}.nes").write_bytes(payload)

    def reject_full_read(_path: Path) -> bytes:
        raise AssertionError("library scan attempted a full Path.read_bytes()")

    monkeypatch.setattr(Path, "read_bytes", reject_full_read)
    entries = GameLibrary(root).scan()
    assert len(entries) == 256
    assert entries[0].game_id == "generated-000.nes"
    assert entries[-1].game_id == "generated-255.nes"
    assert all(entry.supported for entry in entries)


def test_selected_file_disappearing_before_load_is_clear(tmp_path: Path):
    root = tmp_path / "games"
    root.mkdir()
    path = root / "vanishing.nes"
    path.write_bytes(make_ines())
    library = GameLibrary(root)
    entry = library.select(path.name)
    path.unlink()
    with pytest.raises(GameNotLoadableError, match="disappeared before load"):
        library.load_entry(entry)


def test_selected_file_becoming_unsupported_is_revalidated(tmp_path: Path):
    root = tmp_path / "games"
    root.mkdir()
    path = root / "changing.nes"
    path.write_bytes(make_ines())
    library = GameLibrary(root)
    entry = library.select(path.name)
    path.write_bytes(make_ines(flags6=0x20))
    with pytest.raises(GameNotLoadableError, match="changed or is no longer"):
        library.load_entry(entry)


def test_supported_selection_reuses_load_plan_and_mock_transport(tmp_path: Path):
    root = tmp_path / "games"
    root.mkdir()
    payload = make_ines(prg_banks=2, chr_banks=0, flags6=0x01)
    (root / "integration game.nes").write_bytes(payload)

    entry, image = GameLibrary(root).load("integration game.nes")
    plan = LoadPlan.from_image(image)
    transport = MockRuntimeLoaderTransport(
        validation_delay_polls=1,
        activation_delay_polls=2,
    )
    result = execute_load_plan(plan, transport)
    assert entry.supported
    assert result.prg_bytes_written == 2 * PRG_NROM128_BYTES
    assert result.chr_bytes_written == 0
    assert result.status.runtime_active
    assert bytes(transport.prg) == image.prg_bytes


@pytest.mark.parametrize("name", ["Unsupported Mapper 2.nes", "Corrupt Header.nes"])
def test_unsupported_and_corrupt_games_never_reach_transport(
    tmp_path: Path, name: str, monkeypatch: pytest.MonkeyPatch
):
    root = tmp_path / "games"
    write_game_library(root)

    def should_not_load(*_args, **_kwargs):
        raise AssertionError("transport boundary was reached")

    monkeypatch.setattr(loader_cli, "_load_image", should_not_load)
    stderr = StringIO()
    assert (
        run(
            ["load-library", name, "--library", str(root), "--dry-run"],
            stdout=StringIO(),
            stderr=stderr,
        )
        == 2
    )
    assert "unsupported" in stderr.getvalue() or "invalid" in stderr.getvalue()


def test_library_cli_list_info_and_dry_run(tmp_path: Path):
    root = tmp_path / "games"
    write_game_library(root)

    stdout = StringIO()
    assert run(["list", "--library", str(root)], stdout=stdout, stderr=StringIO()) == 0
    report = stdout.getvalue()
    assert report.startswith("Games\n")
    assert "Alpha Test\n   ID: Alpha Test.nes" in report
    assert "Mapper 0 · 16 KiB PRG · 8 KiB CHR-ROM · NROM-128" in report
    assert "Unsupported: Mapper 2" in report
    assert "Invalid: invalid iNES magic" in report

    stdout = StringIO()
    assert (
        run(
            ["info", "Unicode 星.nEs", "--library", str(root)],
            stdout=stdout,
            stderr=StringIO(),
        )
        == 0
    )
    assert "ID: Unicode 星.nEs" in stdout.getvalue()

    stdout = StringIO()
    assert (
        run(
            [
                "load-library",
                "Beta CHR-RAM.NES",
                "--library",
                str(root),
                "--dry-run",
            ],
            stdout=stdout,
            stderr=StringIO(),
        )
        == 0
    )
    report = stdout.getvalue()
    assert "Selected: Beta CHR-RAM (Beta CHR-RAM.NES)" in report
    assert "PRG transfer: 32768 bytes" in report
    assert "CHR transfer: 0 bytes" in report
    assert "Dry run completed successfully" in report


def test_library_root_can_come_from_environment(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
):
    root = tmp_path / "games"
    root.mkdir()
    (root / "environment.nes").write_bytes(make_ines())
    monkeypatch.setenv("NES_LIBRARY_ROOT", str(root))
    stdout = StringIO()
    assert run(["list"], stdout=stdout, stderr=StringIO()) == 0
    assert "environment.nes" in stdout.getvalue()


def test_missing_library_configuration_is_a_normal_cli_error(
    monkeypatch: pytest.MonkeyPatch,
):
    monkeypatch.delenv("NES_LIBRARY_ROOT", raising=False)
    stderr = StringIO()
    assert run(["list"], stdout=StringIO(), stderr=stderr) == 2
    assert "use --library PATH or set NES_LIBRARY_ROOT" in stderr.getvalue()


def test_library_root_must_be_a_directory(tmp_path: Path):
    root = tmp_path / "games"
    root.write_text("not a directory", encoding="utf-8")
    with pytest.raises(LibraryUnavailableError, match="not a directory"):
        GameLibrary(root).scan()


def test_existing_direct_file_cli_remains_compatible(tmp_path: Path):
    image = tmp_path / "direct.nes"
    image.write_bytes(make_ines(chr_banks=0))
    stdout = StringIO()
    assert (
        run(
            ["load", str(image), "--dry-run"],
            stdout=stdout,
            stderr=StringIO(),
        )
        == 0
    )
    assert "PRG transfer: 16384 bytes" in stdout.getvalue()
