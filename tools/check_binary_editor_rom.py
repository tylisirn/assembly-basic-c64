#!/usr/bin/env python3
"""Exercise the binary editor with genuine KERNAL instructions and render VIC state.

The renderer composites character cells and hardware sprites for review. Keyboard
and file bytes are injected; this is not a cycle-accurate VIC/IEC emulator.
"""
from pathlib import Path
import argparse
import hashlib
import json
import struct
import zlib
from check_editor_rom import StockKernelMachine, ROOT


def render(machine, font, destination):
    ram = machine.memory.ram
    palette = [0x000000,0xffffff,0x813338,0x75cec8,0x8e3c97,0x56ac4d,
               0x2e2c9b,0xedf171,0x8e5029,0x553800,0xc46c71,0x4a4a4a,
               0x7b7b7b,0xa9ff9f,0x706deb,0xb2b2b2]
    pixels = [[ram[0xd020]&15 for _ in range(368)] for _ in range(248)]
    background = ram[0xd021]&15
    for y in range(200):
        for x in range(320):
            cell = y//8*40+x//8
            bits = font[ram[0x400+cell]*8+y%8]
            pixels[y+24][x+24] = ram[0xd800+cell]&15 if bits & (128>>(x%8)) else background
    for sprite in reversed(range(8)):
        if not ram[0xd015] & 1<<sprite:
            continue
        sx = ram[0xd000+sprite*2] + (256 if ram[0xd010] & 1<<sprite else 0)
        sy = ram[0xd001+sprite*2]-26
        ex = 2 if ram[0xd01d] & 1<<sprite else 1
        ey = 2 if ram[0xd017] & 1<<sprite else 1
        multi = bool(ram[0xd01c] & 1<<sprite)
        base = ram[0x7f8+sprite]*64
        for y in range(21):
            row = int.from_bytes(ram[base+y*3:base+y*3+3], 'big')
            for x in range(12 if multi else 24):
                value = (row >> ((11-x)*2 if multi else 23-x)) & (3 if multi else 1)
                if not value:
                    continue
                color = ram[0xd027+sprite]&15
                if multi and value == 1: color = ram[0xd025]&15
                if multi and value == 3: color = ram[0xd026]&15
                width = ex*(2 if multi else 1)
                for dy in range(ey):
                    py = sy+y*ey+dy
                    for dx in range(width):
                        px = sx+x*width+dx
                        if 24 <= px < 344 and 24 <= py < 224:
                            pixels[py][px] = color
    rows = []
    for row in pixels:
        data = bytearray()
        for index in row:
            c = palette[index]
            data.extend(bytes((c>>16, c>>8&255, c&255))*2)
        rows.extend((b'\0'+data, b'\0'+data))
    def chunk(kind, data):
        return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data))
    png = b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',736,496,8,2,0,0,0))
    png += chunk(b'IDAT',zlib.compress(b''.join(rows)))+chunk(b'IEND',b'')
    destination.parent.mkdir(parents=True,exist_ok=True)
    destination.write_bytes(png)


def verify(rom_dir, previews):
    m = StockKernelMachine(rom_dir)
    font = (rom_dir/'chargen-901225-01.bin').read_bytes()
    m.command('10 RESERVE $3C00,$200:RESERVE $C000,$300')
    m.command('BASIC')
    m.keys(b'\x87\rNSNS')
    assert m.memory.ram[0x223] == 3
    # First sprite: a small face with exact 24x21 bitmap geometry.
    face = [0x000000,0x03ffc0,0x0ffff0,0x1ffff8,0x3ffffc,0x7ffffe,
            0x738e7e,0x738e7e,0x738e7e,0x7ffffe,0x7ffffe,0x7ffffe,
            0x7ffffe,0x739e7e,0x79fc7e,0x3ffffc,0x1ffff8,0x0ffff0,
            0x03ffc0,0x000000,0x000000]
    hires = b''.join(row.to_bytes(3,'big') for row in face)+b'\x55'
    m.memory.ram[0x3c00:0x3c40] = hires
    multi = bytearray()
    for y in range(21):
        word = 0
        for x in range(12):
            on = bool(face[y] & (3 << ((11-x)*2)))
            color = 0 if not on else (1 if y < 4 else 2)
            if on and y in (6,7,8) and x in (4,7): color = 0
            if on and y in (14,15) and 4 <= x <= 7: color = 1
            word = word<<2 | color
        multi.extend(word.to_bytes(3,'big'))
    multi.append(0xaa)
    m.memory.ram[0x3c40:0x3c80] = multi
    m.keys(b'\rT')
    assert m.memory.ram[0xd01c] == 12
    m.keys(b'C29\rC37\r')  # foreground brown, common highlight yellow
    if previews: render(m,font,previews/'sprite-multicolor.png')
    m.keys(b'__')
    if previews: render(m,font,previews/'reservations.png')
    m.keys(b'\r\x91\r')
    assert m.memory.ram[0xd01c] == 0
    if previews: render(m,font,previews/'sprite-hires.png')
    m.keys(b'C2')
    if previews: render(m,font,previews/'sprite-palette.png')
    m.keys(b'_SFACE\r')
    assert m.files['FACE.BIN'] == hires
    m.files['SHORT.BIN'] = bytearray(b'\xff\0\xaa')
    m.keys(b'LSHORT\r')
    assert bytes(m.memory.ram[0x3c00:0x3c03]) == b'\xff\0\xaa'
    m.keys(b'_CB\r')
    assert m.memory.ram[0xe40] == 2
    if previews: render(m,font,previews/'binary.png')
    m.keys(b'\x88')
    assert m.memory.ram[0x3cc] == 1
    m.keys(b'\x88')
    m.command('SAVE "BINARY.AB",8')
    m.command('NEW')
    m.memory.ram[0x3c00:0x3c80] = bytes(128)
    m.command('LOAD "BINARY.AB",8')
    assert bytes(m.memory.ram[0x3c40:0x3c80]) == multi
    assert bytes(m.memory.ram[0x3c00:0x3c03]) == b'\xff\0\xaa'
    print('Genuine KERNAL: F5, reservations/blobs, sprite modes/colors, BIN I/O, hex view, AB v2 restore passed.')
    return {'passed':True,'rom_sha256':hashlib.sha256(m.memory.rom).hexdigest(),
            'kernal_sha256':hashlib.sha256(m.memory.kernal).hexdigest(),
            'environment':'py65; genuine KERNAL keyboard/output; injected file bytes; software VIC/sprite rendering'}

if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--rom-dir',required=True,type=Path)
    p.add_argument('--previews',type=Path)
    args = p.parse_args()
    report = verify(args.rom_dir,args.previews)
    (ROOT/'build/binary-editor-rom-report.json').write_text(json.dumps(report,indent=2)+'\n')
