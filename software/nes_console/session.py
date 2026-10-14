"""Console lifecycle orchestration using the existing validated load plan."""

from software.nes_loader.ines import load_runtime_image
from software.nes_loader.library import GameLibrary
from software.nes_loader.loader import LoadPlan, execute_load_plan
from .protocol import Command, State


def load_game(console, loader, selection, *, library=None):
    """Validate before BEGIN, then stop, load, activate and await scanout.

    Failure never rolls back runtime storage. A reporting failure must not
    hide the original loader/file exception. The caller owns both transports.
    """
    try:
        image = (GameLibrary(library).load(selection)[1] if library is not None
                 else load_runtime_image(selection))
        plan = LoadPlan.from_image(image)
        console.menu()
        console.request(Command.PREPARE_LOAD)
        result = execute_load_plan(plan, loader)
        console.wait_state(State.MENU)
        console.launch()
        return result
    except Exception:
        try:
            console.request(Command.REPORT_ERROR)
        except Exception:
            pass
        raise
