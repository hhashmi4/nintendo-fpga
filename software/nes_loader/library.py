"""Safe, deterministic removable-media game-library discovery."""

from __future__ import annotations

from dataclasses import dataclass
import os
from pathlib import Path, PurePath
import stat
import unicodedata

from .ines import (
    CHRType,
    INESError,
    INESHeader,
    ImageInspection,
    RuntimeImage,
    inspect_ines_file,
    load_runtime_image,
)


class GameLibraryError(RuntimeError):
    """Base class for expected library and removable-media failures."""


class LibraryNotFoundError(GameLibraryError):
    """The configured removable-media library is not mounted or present."""


class LibraryUnavailableError(GameLibraryError):
    """The configured library exists but cannot be scanned safely."""


class UnsafeGameSelection(GameLibraryError):
    """A selection is not one safe, direct child of the library root."""


class GameNotFoundError(GameLibraryError):
    """No discovered game has the requested stable identity."""


class GameNotLoadableError(GameLibraryError):
    """A corrupt, unsupported, changed, or missing game cannot be loaded."""


@dataclass(frozen=True)
class LibraryEntry:
    """Header-only library metadata keyed by a stable relative-path ID."""

    library_root: Path
    game_id: str
    path: Path
    inspection: ImageInspection | None
    invalid_reason: str | None = None

    @property
    def filename(self) -> str:
        return self.game_id

    @property
    def display_name(self) -> str:
        return Path(self.game_id).stem

    @property
    def valid(self) -> bool:
        return self.inspection is not None and self.invalid_reason is None

    @property
    def supported(self) -> bool:
        return self.valid and bool(self.inspection and self.inspection.supported)

    @property
    def reason(self) -> str | None:
        if self.invalid_reason is not None:
            return self.invalid_reason
        return self.inspection.reason if self.inspection is not None else None

    @property
    def header(self) -> INESHeader | None:
        return self.inspection.header if self.inspection is not None else None

    @property
    def mapper(self) -> int | None:
        return self.header.mapper if self.header is not None else None

    @property
    def prg_size(self) -> int | None:
        return self.header.prg_bytes if self.header is not None else None

    @property
    def chr_size(self) -> int | None:
        return self.header.chr_bytes if self.header is not None else None

    @property
    def chr_type(self) -> CHRType | None:
        if self.header is None:
            return None
        return CHRType.RAM if self.header.chr_banks == 0 else CHRType.ROM

    @property
    def mirroring_name(self) -> str | None:
        if self.header is None:
            return None
        if self.header.four_screen:
            return "Four-screen"
        return "Vertical" if self.header.vertical_mirroring else "Horizontal"

    @property
    def nrom_mode(self) -> str | None:
        if self.header is None or self.header.mapper != 0:
            return None
        if self.header.prg_banks == 1:
            return "NROM-128"
        if self.header.prg_banks == 2:
            return "NROM-256"
        return None


def _sort_key(entry: LibraryEntry) -> tuple[str, str, str]:
    normalized = unicodedata.normalize("NFC", entry.game_id)
    return normalized.casefold(), normalized, entry.game_id


def _os_error_text(error: OSError) -> str:
    return error.strerror or str(error)


class GameLibrary:
    """A non-recursive library rooted at one configured directory.

    File extensions are matched case-insensitively. Symlinks, directories, and
    non-regular files are never opened or returned as games.
    """

    def __init__(self, root: str | Path) -> None:
        self.configured_root = Path(root).expanduser()

    def _canonical_root(self) -> Path:
        try:
            root = self.configured_root.resolve(strict=True)
        except FileNotFoundError as error:
            raise LibraryNotFoundError(
                f"library not mounted or not found: {self.configured_root}"
            ) from error
        except OSError as error:
            raise LibraryUnavailableError(
                f"cannot access library {self.configured_root}: "
                f"{_os_error_text(error)}"
            ) from error
        if not root.is_dir():
            raise LibraryUnavailableError(f"library root is not a directory: {root}")
        return root

    def scan(self) -> tuple[LibraryEntry, ...]:
        root = self._canonical_root()
        entries: list[LibraryEntry] = []
        try:
            with os.scandir(root) as directory:
                for item in directory:
                    if not item.name.casefold().endswith(".nes"):
                        continue
                    try:
                        metadata = item.stat(follow_symlinks=False)
                    except OSError as error:
                        entries.append(
                            LibraryEntry(
                                root,
                                item.name,
                                root / item.name,
                                None,
                                f"cannot inspect file: {_os_error_text(error)}",
                            )
                        )
                        continue
                    if item.is_symlink() or not stat.S_ISREG(metadata.st_mode):
                        continue

                    path = root / item.name
                    try:
                        inspection = inspect_ines_file(path)
                    except INESError as error:
                        entries.append(
                            LibraryEntry(root, item.name, path, None, str(error))
                        )
                    except OSError as error:
                        entries.append(
                            LibraryEntry(
                                root,
                                item.name,
                                path,
                                None,
                                f"cannot read file: {_os_error_text(error)}",
                            )
                        )
                    else:
                        entries.append(
                            LibraryEntry(root, item.name, path, inspection)
                        )
        except FileNotFoundError as error:
            raise LibraryNotFoundError(
                f"library disappeared while scanning: {self.configured_root}"
            ) from error
        except OSError as error:
            raise LibraryUnavailableError(
                f"cannot scan library {root}: {_os_error_text(error)}"
            ) from error
        return tuple(sorted(entries, key=_sort_key))

    @staticmethod
    def _validate_game_id(game_id: str) -> None:
        if "\x00" in game_id:
            raise UnsafeGameSelection("game ID contains a NUL byte")
        relative = PurePath(game_id)
        if (
            not game_id
            or relative.is_absolute()
            or len(relative.parts) != 1
            or relative.parts[0] in (".", "..")
        ):
            raise UnsafeGameSelection(
                "game ID must be one library-relative filename; traversal and "
                "nested paths are not allowed"
            )

    def select(self, game_id: str) -> LibraryEntry:
        self._validate_game_id(game_id)
        for entry in self.scan():
            if entry.game_id == game_id:
                return entry

        root = self._canonical_root()
        candidate = root / game_id
        try:
            if candidate.is_symlink():
                raise UnsafeGameSelection("symlinked games are not allowed")
        except OSError as error:
            raise LibraryUnavailableError(
                f"cannot inspect selected game {game_id}: {_os_error_text(error)}"
            ) from error
        raise GameNotFoundError(f"game is not present in the library: {game_id}")

    def _safe_current_path(self, game_id: str, expected_root: Path) -> Path:
        self._validate_game_id(game_id)
        root = self._canonical_root()
        if root != expected_root:
            raise GameNotLoadableError(
                "library media changed after selection; scan and select again"
            )
        candidate = root / game_id
        try:
            metadata = candidate.lstat()
        except FileNotFoundError as error:
            raise GameNotLoadableError(
                f"selected game disappeared before load: {game_id}"
            ) from error
        except OSError as error:
            raise GameNotLoadableError(
                f"cannot access selected game {game_id}: {_os_error_text(error)}"
            ) from error
        if stat.S_ISLNK(metadata.st_mode):
            raise UnsafeGameSelection("symlinked games are not allowed")
        if not stat.S_ISREG(metadata.st_mode):
            raise UnsafeGameSelection("selected game is not a regular file")
        try:
            resolved = candidate.resolve(strict=True)
        except OSError as error:
            raise GameNotLoadableError(
                f"cannot resolve selected game {game_id}: {_os_error_text(error)}"
            ) from error
        if resolved.parent != root:
            raise UnsafeGameSelection("selected game escapes the library root")
        return resolved

    def load_entry(self, entry: LibraryEntry) -> RuntimeImage:
        if not entry.supported:
            status = "invalid" if not entry.valid else "unsupported"
            reason = entry.reason or "no reason available"
            raise GameNotLoadableError(
                f"selected game is {status}: {entry.game_id}: {reason}"
            )
        path = self._safe_current_path(entry.game_id, entry.library_root)
        try:
            return load_runtime_image(path, follow_symlinks=False)
        except OSError as error:
            raise GameNotLoadableError(
                f"cannot read selected game {entry.game_id}: "
                f"{_os_error_text(error)}"
            ) from error
        except INESError as error:
            raise GameNotLoadableError(
                f"selected game changed or is no longer loadable: "
                f"{entry.game_id}: {error}"
            ) from error

    def load(self, game_id: str) -> tuple[LibraryEntry, RuntimeImage]:
        entry = self.select(game_id)
        return entry, self.load_entry(entry)
