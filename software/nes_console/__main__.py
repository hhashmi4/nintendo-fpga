"""Run with python3 -m software.nes_console on the HPS."""

import argparse
from contextlib import ExitStack
import fcntl
import os
import time
import sys
from pathlib import Path

from software.nes_loader.mmio import DevMemMmio
from software.nes_loader.mmio_registers import MMIO_PHYSICAL_BASE, MMIO_SPAN_BYTES
from software.nes_loader.transport import MmioRuntimeLoaderTransport
from .protocol import Command, State, PHYSICAL_BASE, SPAN_BYTES
from .session import load_game
from .transport import ConsoleTransport


def main():
    parser = argparse.ArgumentParser(description="Independent NES console control")
    parser.add_argument("action", choices=("status", "menu", "launch", "developer", "load", "serve"))
    parser.add_argument("selection", nargs="?")
    parser.add_argument("--library", type=Path)
    parser.add_argument("--metadata", type=Path)
    parser.add_argument("--dev-mem", default="/dev/mem")
    parser.add_argument("--lock", default="/run/lock/nes-console.lock")
    args = parser.parse_args()
    if args.action == "load" and args.selection is None:
        parser.error("load requires a file or library game ID")
    if args.action == "serve":
        from .library_protocol import LibraryTransport, PHYSICAL_BASE as LIB_BASE, SPAN_BYTES as LIB_SPAN
        from .library_service import LibraryService, read_titles
        root = args.library or os.environ.get("NES_LIBRARY_ROOT")
        if not root:
            parser.error("serve requires --library PATH or NES_LIBRARY_ROOT")
        try:
            titles = read_titles(args.metadata)
        except (ValueError, OSError, RuntimeError) as error:
            print(f"Optional title metadata ignored: {error}", file=sys.stderr)
            titles = {}
        with ExitStack() as stack:
            lock = stack.enter_context(open(args.lock, "a"))
            console = ConsoleTransport(stack.enter_context(DevMemMmio(PHYSICAL_BASE, SPAN_BYTES, device=args.dev_mem)))
            library = LibraryTransport(stack.enter_context(DevMemMmio(LIB_BASE, LIB_SPAN, device=args.dev_mem)))
            loader = MmioRuntimeLoaderTransport(stack.enter_context(DevMemMmio(MMIO_PHYSICAL_BASE, MMIO_SPAN_BYTES, device=args.dev_mem)))
            service = LibraryService(console, library, loader, root, titles=titles)
            reported_error = None
            try:
                while True:
                    fcntl.flock(lock, fcntl.LOCK_EX)
                    try:
                        service.step()
                    finally:
                        fcntl.flock(lock, fcntl.LOCK_UN)
                    if service.last_error != reported_error:
                        reported_error = service.last_error
                        if reported_error:
                            print(reported_error, file=sys.stderr)
                    time.sleep(0.05)
            except KeyboardInterrupt:
                return
        return
    with ExitStack() as stack:
        lock = stack.enter_context(open(args.lock, "a"))
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        console = ConsoleTransport(stack.enter_context(DevMemMmio(
            PHYSICAL_BASE, SPAN_BYTES, device=args.dev_mem)))
        if args.action == "load":
            loader = MmioRuntimeLoaderTransport(stack.enter_context(DevMemMmio(
                MMIO_PHYSICAL_BASE, MMIO_SPAN_BYTES, device=args.dev_mem)))
            load_game(console, loader, args.selection, library=args.library)
        elif args.action == "developer":
            before = console.request(Command.DEVELOPER)
            console.wait_state(State.DEVELOPER, epoch=(before.epoch + 1) & 0xFFFF)
        elif args.action == "menu":
            console.menu()
        elif args.action == "launch":
            console.launch()
        print(console.status())


if __name__ == "__main__":
    main()
