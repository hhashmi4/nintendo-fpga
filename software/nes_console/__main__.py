"""Run with python3 -m software.nes_console on the HPS."""

import argparse
from contextlib import ExitStack
import fcntl
from pathlib import Path

from software.nes_loader.mmio import DevMemMmio
from software.nes_loader.mmio_registers import MMIO_PHYSICAL_BASE, MMIO_SPAN_BYTES
from software.nes_loader.transport import MmioRuntimeLoaderTransport
from .protocol import Command, State, PHYSICAL_BASE, SPAN_BYTES
from .session import load_game
from .transport import ConsoleTransport


def main():
    parser = argparse.ArgumentParser(description="Independent NES console control")
    parser.add_argument("action", choices=("status", "menu", "launch", "developer", "load"))
    parser.add_argument("selection", nargs="?")
    parser.add_argument("--library", type=Path)
    parser.add_argument("--dev-mem", default="/dev/mem")
    parser.add_argument("--lock", default="/run/lock/nes-console.lock")
    args = parser.parse_args()
    if args.action == "load" and args.selection is None:
        parser.error("load requires a file or library game ID")
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
