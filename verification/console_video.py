"""Independent paint-based oracle; never reads RTL, design tokens, or DUT pixels."""
from .debug_renderer import FONT_5X8

PALETTE = dict(bg=0x17151C, surface=0x25222C, purple=0x493753, red=0xC44B58,
               text=0xF0E9DC, muted=0xB4ADBA, success=0x94C5A5,
               warning=0xE2BE78, error=0xF18B92)
TITLES = ['INITIALIZING', 'READY TO PLAY', 'LOADING CARTRIDGE', 'STARTING GAME',
          'GAME ACTIVE', 'RETURNING TO MENU', 'LOAD NEEDS ATTENTION', 'DEVELOPER MODE']
ERRORS = ['NO ERROR REPORTED', 'WRONG LOADER STATE', 'LOADER ALREADY BUSY',
          'INVALID LOADER COMMAND', 'INVALID WRITE TARGET', 'INVALID WRITE ADDRESS',
          'EMPTY CARTRIDGE LOAD', 'INVALID ROM MANIFEST', 'UNSUPPORTED MAPPER',
          'UNSUPPORTED PRG SIZE', 'UNSUPPORTED CHR SIZE', 'OUT OF ORDER WRITE',
          'PRG DATA INCOMPLETE', 'CHR DATA INCOMPLETE', 'ACTIVATION INVALID',
          'GAME FRAME TIMEOUT']


def screen_lines(status, buttons, held_reset, focus=False):
    state, available, error, loader = status & 15, bool(status & 256), (status >> 12) & 15, (status >> 10) & 3
    first = ['PREPARING CONSOLE', 'PLAY GAME' if available else 'PLAY GAME - UNAVAILABLE',
             ['WAITING FOR HPS TRANSFER', 'RECEIVING GAME DATA', 'IMAGE READY TO ACTIVATE', 'CHECKING LOAD RESULT'][loader], 'WAITING FOR COMPLETE FRAME', 'GAME OWNS DISPLAY',
             'RESTORING SYSTEM DISPLAY', ERRORS[error], 'DEVELOPER MODE'][state]
    if state == 6 and error == 14 and loader != 3:
        first = 'HOST LOAD REQUEST FAILED'
    second = 'DEVELOPER MODE' if state == 1 else ('DISPLAY HANDOFF IN PROGRESS' if state in (0, 3, 4, 5) else 'B - RETURN TO MENU')
    detail = {1: 'LIBRARY / SETTINGS - LATER', 2: 'TRANSFER CONTROLLED BY HPS',
              6: f'ERROR {error:X}  LOADER  {loader:X}',
              7: f'RESET {int(held_reset)}  LOAD  {loader:X}  ERROR {error:X}'}.get(state, 'INDEPENDENT SYSTEM DISPLAY')
    status_text = 'CARTRIDGE READY' if available else 'NO CARTRIDGE AVAILABLE'
    status_color = 'success' if available else 'warning'
    if state == 6:
        status_text, status_color = 'RETRY WITH A COMPLETE LOAD', 'warning'
    if state == 7:
        status_text, status_color = f'EPOCH {status >> 16:04X} BUTTONS  {buttons:02X}', 'muted'
    return [(56, 40, 'NINTENDO FPGA', 'text'), (56, 72, 'START PLAY / SELECT DEV' if state == 1 else 'CONSOLE / SYSTEM', 'muted'),
            (56, 152, TITLES[state], 'error' if state == 6 else 'text'),
            (56, 216, first, 'muted' if state == 1 and not available else 'text'),
            (56, 264, second, 'text'), (56, 320, detail, 'muted'),
            (56, 392, status_text, status_color),
            (56, 424, ['SYSTEM INITIALIZATION', 'UP/DOWN FOCUS  A SELECT', 'RELOAD AFTER INTERRUPTION', 'FIRST FRAME REQUIRED', 'HPS MENU TO RETURN', 'PLEASE WAIT', 'SELECT - DEVELOPER', 'DIAGNOSTICS REMAIN AVAILABLE'][state], 'muted')]


def console_pixels(status: int, buttons: int, held_reset: bool, *, focus=False,
                   splash=False, phase=0, valid=True) -> list[int]:
    pixels = [PALETTE['bg']] * (640 * 480)
    def rect(x, y, w, h, color):
        for py in range(y, y + h):
            pixels[py * 640 + x:py * 640 + x + w] = [PALETTE[color]] * w
    def text(x, y, line, color, scale=2):
        for column, character in enumerate(line):
            for gy, row in enumerate(FONT_5X8[character]):
                for gx, bit in enumerate(row):
                    if bit == '1':
                        rect(x + column * 8 * scale + gx * scale, y + gy * scale, scale, scale, color)
    if not valid:
        return [0] * (640 * 480)
    state = status & 15
    if splash:
        rect(288, 120, 32, 32, 'purple'); rect(320, 120, 32, 32, 'red')
        text(112, 184, 'NINTENDO FPGA', 'text', 4)
        text(184, 256, 'A NEW WAY TO PLAY', 'muted')
        rect(288, 304, 64, 4, 'purple'); rect(288, 304, 16 + (phase // 8) * 16, 4, 'red')
        return pixels
    right = 496 if state == 7 else 608
    rect(32, 128, right-32, 224, 'surface')
    rect(32, 96, 576, 2, 'purple'); rect(32, 96, 48, 2, 'red')
    if state == 1:
        rect(44, 204 + 48 * focus, right-56, 40, 'purple')
        rect(44, 204 + 48 * focus, 4, 40, 'text')
    if state in (2, 3, 5):
        for n in range(4):
            rect(56+n*16, 184, 8, 8, 'text' if n == phase // 8 else 'purple')
    for x, y, line, color in screen_lines(status, buttons, held_reset, focus):
        text(x, y, line, color)
    return pixels


def visual_fixtures():
    # All original eight states plus every error code, splash stages, motion
    # phases, both focus targets, disabled/available actions and host error.
    result = [(0x12348E00 | state, False, False, 0) for state in range(8)]
    result += [(0x12340C06 | error << 12, False, False, 0) for error in range(16)]
    result += [(0x12340101, False, True, phase) for phase in (0, 8, 16)]
    result += [(0x12340402, False, False, phase) for phase in (8, 16, 24)]
    result += [(0x12340101, focus, False, 0) for focus in (False, True)]
    result += [(0x1234E006, False, False, 0)]
    result += [(0x00000101, False, False, 0)]  # legitimate epoch wrap
    result += [(0x12340002 | loader << 10, False, False, 0) for loader in (0, 2)]
    return result
