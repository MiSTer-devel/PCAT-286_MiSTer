"""Execute the patched ROM's initialization, IRQ1 and INT 16h paths.

Requires Unicorn (Python package). This is a focused 16-bit CPU test with
port callbacks, not a simulation of SPK286 or a complete PC/86Box boot.
"""

import argparse
import hashlib
import struct
from pathlib import Path

from unicorn import Uc, UC_ARCH_X86, UC_MODE_16, UC_HOOK_CODE, UC_HOOK_INSN
from unicorn.x86_const import (
    UC_X86_INS_IN, UC_X86_INS_OUT, UC_X86_REG_AX, UC_X86_REG_BX,
    UC_X86_REG_CS, UC_X86_REG_DS, UC_X86_REG_SS, UC_X86_REG_SP,
    UC_X86_REG_EFLAGS,
)


ROM_BASE = 0xF0000
BDA = 0x400
RETURN_ADDRESS = 0x7000


class RomTest:
    def __init__(self, rom):
        self.cpu = Uc(UC_ARCH_X86, UC_MODE_16)
        self.cpu.mem_map(0, 0x110000)
        self.cpu.mem_write(ROM_BASE, rom)
        # Poison the BDA so a skipped buffer initialization cannot pass.
        self.cpu.mem_write(BDA, bytes([0xCC]) * 0x100)
        self.cpu.reg_write(UC_X86_REG_CS, 0xF000)
        self.cpu.reg_write(UC_X86_REG_DS, 0x40)
        self.cpu.reg_write(UC_X86_REG_SS, 0)
        self.cpu.reg_write(UC_X86_REG_SP, 0x8000)
        self.cpu.reg_write(UC_X86_REG_EFLAGS, 2)
        self.ports = []
        self.visited = set()
        self.command_byte = 1
        self.write_command_byte = False
        self.enabled = True
        self.output_byte = None
        self.cpu.hook_add(UC_HOOK_CODE, self.on_code)
        self.cpu.hook_add(UC_HOOK_INSN, self.on_in, None, 1, 0, UC_X86_INS_IN)
        self.cpu.hook_add(UC_HOOK_INSN, self.on_out, None, 1, 0, UC_X86_INS_OUT)

    def on_code(self, cpu, address, size, _):
        self.visited.add(address)

    def on_in(self, cpu, port, size, _):
        assert size == 1
        if port == 0x60:
            assert self.output_byte is not None, 'Read of empty keyboard buffer'
            value = self.output_byte
            self.output_byte = None
        elif port == 0x64:
            value = 0x10 | (self.command_byte & 4) | int(self.output_byte is not None)
        else:
            raise AssertionError(f'Unexpected IN from {port:04X}')
        self.ports.append(('in', port, value))
        return value

    def on_out(self, cpu, port, size, value, _):
        assert size == 1
        self.ports.append(('out', port, value))
        if port == 0x64:
            if value == 0x60:
                self.write_command_byte = True
            elif value == 0xAE:
                self.enabled = True
                self.command_byte &= ~0x10
            else:
                raise AssertionError(f'Unexpected 8042 command {value:02X}')
        elif port == 0x60:
            assert self.write_command_byte
            self.command_byte = value
            self.enabled = not (value & 0x10)
            self.write_command_byte = False
        else:
            assert port in (0x20, 0x21, 0x80), f'Unexpected OUT to {port:04X}'

    def word(self, offset):
        return int.from_bytes(self.cpu.mem_read(BDA + offset, 2), 'little')

    def init(self):
        # Start just after the three PIT-test notes. Run the actual original
        # PIC setup, replacement KBC setup, buffer CALL, POST 09 and STI.
        stop = ROM_BASE + 0xE20B
        self.cpu.emu_start(ROM_BASE + 0xE1C9, stop, count=1000)
        assert ROM_BASE + 0xEB9D in self.visited, 'kbd_buffer_init was never called'
        assert ('out', 0x80, 0x09) in self.ports, 'POST 09 was not reached'
        assert ('out', 0x21, 0xBC) in self.ports, 'PIC keyboard IRQ was not unmasked'
        assert self.cpu.reg_read(UC_X86_REG_EFLAGS) & 0x200
        assert self.cpu.reg_read(UC_X86_REG_SP) == 0x8000, 'Unbalanced init stack'
        assert self.enabled and self.command_byte & 1
        assert self.word(0x80) == self.word(0x1A) == self.word(0x1C) == 0x1E
        assert self.word(0x82) == 0x3E
        assert self.word(0x17) == self.word(0x96) == 0
        print('PASS: post-beep initialization reaches POST 09, initializes BDA and enables IRQ1')

    def interrupt(self, offset):
        # Supply the hardware INT stack frame and execute the real handler
        # through its IRET (or INT 16h RETF 2) back to a sentinel in RAM.
        sp = 0x8000
        flags = self.cpu.reg_read(UC_X86_REG_EFLAGS) & 0xFFFF
        frame = struct.pack('<HHH', RETURN_ADDRESS, 0, flags)
        self.cpu.mem_write(sp - len(frame), frame)
        self.cpu.reg_write(UC_X86_REG_SS, 0)
        self.cpu.reg_write(UC_X86_REG_SP, sp - len(frame))
        self.cpu.reg_write(UC_X86_REG_CS, 0xF000)
        self.cpu.reg_write(UC_X86_REG_EFLAGS, flags & ~0x300)
        self.cpu.emu_start(ROM_BASE + offset, RETURN_ADDRESS, count=5000)
        assert self.cpu.reg_read(UC_X86_REG_CS) == 0, 'Interrupt did not return'
        assert self.cpu.reg_read(UC_X86_REG_SP) == sp, 'Unbalanced interrupt stack'

    def key(self, scan):
        assert self.output_byte is None and self.enabled
        self.output_byte = scan
        old_ax, old_bx, old_ds = 0x1234, 0x5678, 0x2345
        self.cpu.reg_write(UC_X86_REG_AX, old_ax)
        self.cpu.reg_write(UC_X86_REG_BX, old_bx)
        self.cpu.reg_write(UC_X86_REG_DS, old_ds)
        start = len(self.ports)
        self.interrupt(0xE987)
        assert self.output_byte is None, 'IRQ1 did not consume port 60h'
        assert self.ports[start:] == [('in', 0x60, scan), ('out', 0x20, 0x20)]
        assert self.cpu.reg_read(UC_X86_REG_AX) == old_ax
        assert self.cpu.reg_read(UC_X86_REG_BX) == old_bx
        assert self.cpu.reg_read(UC_X86_REG_DS) == old_ds

    def read_key(self, expected):
        self.cpu.reg_write(UC_X86_REG_AX, 0x0100)
        self.interrupt(0xE82E)
        assert not (self.cpu.reg_read(UC_X86_REG_EFLAGS) & 0x40), 'INT 16h reports no key'
        assert self.cpu.reg_read(UC_X86_REG_AX) == expected
        self.cpu.reg_write(UC_X86_REG_AX, 0)
        self.interrupt(0xE82E)
        assert self.cpu.reg_read(UC_X86_REG_AX) == expected
        assert self.word(0x1A) == self.word(0x1C), 'INT 16h did not consume the key'

    def keyboard(self):
        self.key(0x1E)  # A make, translated scan-code set 1
        self.key(0x9E)  # A break must not enqueue a second character
        self.read_key(0x1E61)  # a
        self.key(0x2A)  # Left Shift make
        self.key(0x1E)
        self.key(0x9E)
        self.key(0xAA)  # Left Shift break
        self.read_key(0x1E41)  # A
        self.key(0x1C)  # Enter
        self.key(0x9C)
        self.read_key(0x1C0D)
        assert not (self.word(0x17) & 2), 'Left Shift remains pressed'
        print('PASS: IRQ1/INT 16h deliver a, Shift+A and Enter with make/break and PIC EOI')

    def keyboard_trace(self, path):
        # Consume bytes actually read from the RTL 8042 simulation for HPS
        # A/B/Shift+A/Enter events, rather than supplying already-correct
        # set-1 codes. Extra characters on key release fail this check.
        expected = [0x1E61, 0x3062, 0x1E41, 0x1C0D]
        delivered = 0
        for token in path.read_text().split():
            self.key(int(token, 16))
            if self.word(0x1A) != self.word(0x1C):
                assert delivered < len(expected), 'Duplicate key from RTL trace'
                self.read_key(expected[delivered])
                delivered += 1
        assert delivered == len(expected), 'Missing keys from RTL trace'
        assert not (self.word(0x17) & 2), 'Left Shift remains pressed'
        print('PASS: actual RTL HPS/8042 trace -> ROM IRQ1/INT 16h delivers exactly abA+Enter')


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('rom', nargs='?', type=Path, default=root / 'SW/ROMs/xtsergey_mod_at.rom')
    parser.add_argument('--scan-trace', type=Path, help='scan_trace.txt from test_at_keyboard.sh')
    args = parser.parse_args()
    rom = args.rom.read_bytes()
    assert len(rom) == 65536
    assert sum(rom) & 0xFF == 0, 'ROM checksum is invalid'
    test = RomTest(rom)
    test.init()
    if args.scan_trace:
        test.keyboard_trace(args.scan_trace)
    else:
        test.keyboard()
    print(f'PASS: 64 KiB, checksum 00h, SHA256={hashlib.sha256(rom).hexdigest().upper()}')


if __name__ == '__main__':
    main()
