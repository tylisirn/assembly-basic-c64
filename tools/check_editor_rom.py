#!/usr/bin/env python3
"""Exercise the split editor with a supplied 901227-03 C64 KERNAL ROM.

CPU-level validation: actual RESTOR/CINT/GETIN/CHRIN/CHROUT instructions, injected
keyboard queue bytes, and synthetic raster registers. No VIC/IEC cycle claims.
ROMs are user supplied and are never included in the cartridge or repository.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import sys
import zlib

ROOT = Path(__file__).resolve().parents[1]
for path in ('host', '.tools/py65'):
    sys.path.insert(0, str(ROOT/path))
from ab64.emulator import Machine


class StockKernelMachine(Machine):
    def __init__(self, rom_dir):
        self.real_kernel = False
        super().__init__()
        self.boot()
        rom = (rom_dir/'kernal-901227-03.bin').read_bytes()
        if len(rom) != 8192:
            raise ValueError('Expected an 8192-byte 901227-03 KERNAL ROM')
        self.memory.kernal[:] = rom
        self.memory.ram[0x288] = 4
        saved = (self.cpu.pc, self.cpu.sp)
        self.invoke_rom(0xff8a)  # RESTOR initializes every KERNAL RAM vector
        self.invoke_rom(0xff5b)  # CINT initializes screen/VIC/keyboard state
        self.cpu.pc, self.cpu.sp = saved
        self.real_kernel = True

    def invoke_rom(self, address):
        self.cpu.stPushWord(0x6ff)
        self.cpu.pc = address
        for _ in range(100000):
            if self.cpu.pc == 0x700:
                return
            # CINT waits for raster zero and checks the raster IRQ flag.
            self.memory.ram[0xd012] = 0
            self.memory.ram[0xd019] = 1
            self.cpu.step()
        raise AssertionError(f'ROM initialization did not return: ${self.cpu.pc:04X}')

    def step(self):
        c = self.cpu
        keyboard_input = (c.pc == 0xffcf and not self.input_channel and
                          self.word(0x324) == self.labels['editor_input_gate'])
        if (self.real_kernel and self.memory.ram[1] & 2 and
                ((c.pc in (0xffd2, 0xffe4, 0xffe1) and not (c.pc == 0xffd2 and self.output_channel)) or keyboard_input)):
            if c.pc == 0xffd2:
                self.output.append(c.a)
            elif c.pc == 0xffe4:
                self.memory.ram[0xc6] = int(bool(self.input))
                if self.input:
                    self.memory.ram[0x277] = self.input.pop(0)
            c.step()
            self.steps += 1
            return True
        return super().step()

    def keys(self, keys):
        self.input.extend(keys)
        self.pump()


def verify(rom_dir):
    m = StockKernelMachine(rom_dir)
    for source in ('10 PRINT 77', '20 REM '+'X'*65):
        m.command(source)
    m.memory.ram[0x91] = 0xff
    assert '20 REM' in m.command('LIST')
    m.memory.ram[0x91] = 0x7f  # actual KERNAL STOP matrix state
    assert '10 PRINT' not in m.command('LIST')
    m.memory.ram[0x91] = 0xff
    m.command('BASIC')
    assert m.memory.ram[0x3cc] == 1
    assert m.word(0x326) == m.labels['editor_output_gate']
    assert m.memory.ram[0x400:0x402] == bytes((177, 176))
    assert m.memory.ram[0x403] == 16  # PRINT remains in normal video
    m.keys(b'\r')
    assert bytes(m.memory.ram[0xa60:0xa6b]) == b'10 PRINT 77'
    m.keys(b'\x85')
    assert m.memory.ram[0x400+4*40] == 31  # PETSCII 95's screen glyph
    m.keys(b' \x14' + b'9\r')
    m.keys(b'PRINT 123\r')
    assert b' 123 ' in m.output
    m.keys(b'\x91\x91')
    assert bytes(m.memory.ram[0xa60:0xa69]) == b'PRINT 123'
    m.keys(b'__')
    m.keys(b'AB\x9d\x94\x05\x93\x05')
    assert bytes(m.memory.ram[0xa60:0xa62]) == b'A\x93'
    assert m.memory.ram[0x3cc+2] == 1
    m.keys(b'\x94__')
    m.keys(b'INPUT A$:PRINT A$\r')
    assert m.cpu.pc == m.labels['editor_input_wait']
    m.keys(b'HELLO\x85 \r')
    assert b'HELLO' in m.output
    m.keys(b'PRINT CHR$(147):PRINT 1/0\r')
    draft = b'PRINT CHR$(147):PRINT 1/0'
    assert bytes(m.memory.ram[0xa60:0xa60+len(draft)]) == draft
    assert m.memory.ram[0x3cc+16] == 0
    m.keys(b'__RUN\r')
    assert m.memory.ram[0x3cc] == 0
    assert m.word(0x326) == 0xf1ca
    assert m.word(0x324) == 0xf157
    assert b' 79 ' in m.output
    assert m.memory.bank == 0
    # Scroll mixed-width source in both directions with the real keyboard API,
    # then compare the retained screen with a newly opened viewport.
    m.command('NEW')
    for number in range(10, 311, 10):
        width = 50 if number % 30 == 0 else 5
        m.command(f'{number} REM '+ 'X'*width)
    m.command('BASIC')
    colors = bytes(m.memory.ram[0xd800:0xdb20])
    m.keys(b'\x11'*19+b'\x91'*15)
    screen = bytes(m.memory.ram[0x400:0x720])
    assert bytes(m.memory.ram[0xd800:0xdb20]) == colors
    m.keys(b'\x88')
    m.command('BASIC')
    assert bytes(m.memory.ram[0x400:0x720]) == screen
    m.keys(b'\x8610\r\x86260\r')
    assert (m.word(0x3cf), m.word(0x3d1)) == (260, 230)
    row = m.memory.ram[0x3cc+50]
    assert bytes(m.memory.ram[0x400+row*40:0x403+row*40]) == b'\xb2\xb6\xb0'
    m.keys(b'\x88')
    # Device bytes are supplied by the file harness; keyboard/output still
    # execute the real KERNAL. This adds no IEC/disk timing claim.
    m.files['STOCK'] = bytearray.fromhex('010809080a00993432000000')
    m.command('LOAD "STOCK",8')
    assert '10 PRINT 42' in m.command('LIST')
    assert ' 42 ' in m.command('RUN')
    print('Stock 901227-03 KERNAL: RESTOR/CINT, GETIN, CHRIN, CHROUT, '
          'STOP/LIST, F1/95 glyph, F3/context, PRG import, number cursor, scrolling, editing, PRINT, INPUT, '
          'error retention and RUN/exit passed.')
    return {'kernal': '901227-03', 'passed': True,
            'rom_sha256': hashlib.sha256(m.memory.rom).hexdigest(),
            'kernal_sha256': hashlib.sha256(m.memory.kernal).hexdigest(),
            'environment': 'py65; actual KERNAL editor/I/O instructions; '
                           'injected keyboard bytes and synthetic raster; no VIC/IEC timing'}


def preview(rom_dir, destination):
    m = StockKernelMachine(rom_dir)
    for line in (ROOT/'examples/voidrunner.bas').read_text().splitlines():
        if 370 <= int(line.split()[0]) <= 500:
            m.command(line)
    m.command('BASIC')
    m.keys(b'\x11'*6+b'\r')
    font = (rom_dir/'chargen-901225-01.bin').read_bytes()
    if len(font) != 4096:
        raise ValueError('Expected a 4096-byte 901225-01 character ROM')
    palette = [0x000000, 0xffffff, 0x813338, 0x75cec8, 0x8e3c97, 0x56ac4d,
               0x2e2c9b, 0xedf171, 0x8e5029, 0x553800, 0xc46c71, 0x4a4a4a,
               0x7b7b7b, 0xa9ff9f, 0x706deb, 0xb2b2b2]
    colors = [bytes((c >> 16, c >> 8 & 255, c & 255)) for c in palette]
    ram = m.memory.ram
    width, height = 736, 496
    border, background = ram[0xd020] & 15, ram[0xd021] & 15
    rows = []
    for y in range(height):
        row = bytearray()
        for x in range(width):
            color = border
            if 48 <= x < 688 and 48 <= y < 448:
                sx, sy = (x-48)//2, (y-48)//2
                cell = sy//8*40 + sx//8
                character = ram[0x400+cell]
                bits = font[character*8 + sy%8]
                color = ram[0xd800+cell] & 15 if bits & (128 >> (sx%8)) else background
            row.extend(colors[color])
        rows.append(b'\0'+row)
    def chunk(kind, data):
        return struct.pack('>I', len(data))+kind+data+struct.pack('>I', zlib.crc32(kind+data))
    png = b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR', struct.pack('>IIBBBBB', width,height,8,2,0,0,0))
    png += chunk(b'IDAT', zlib.compress(b''.join(rows)))+chunk(b'IEND', b'')
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(png)
    print(f'Editor preview: {destination}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--rom-dir', required=True, type=Path)
    parser.add_argument('--preview', type=Path)
    args = parser.parse_args()
    result = verify(args.rom_dir)
    (ROOT/'build/editor-rom-report.json').write_text(json.dumps(result, indent=2)+'\n')
    if args.preview:
        preview(args.rom_dir, args.preview)
