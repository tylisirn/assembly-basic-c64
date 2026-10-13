#!/usr/bin/env python3
"""Reproducible eight-bank Magic Desk build and CRT packaging."""
import argparse
import hashlib
import json
from pathlib import Path
import os
import re
import shutil
import struct
import subprocess
import sys
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'host'))
from ab64.tokens import KEYWORDS

BANK_ROLES = (
    'boot, command editor, tokenizer, LIST and source transport',
    'raw resident compiler image',
    'raw RAM execution runtime image and banked ROM services',
    'reserved: improved editor and BASIC PRG conversion',
    'reserved: 16.16 fixed-point and PRINT formatting extensions',
    'reserved: sprite, VIC and SID commands',
    'reserved: numeric tables, fonts and optional resources',
    'reserved: expansion and diagnostics',
)


def build(toolchain=None):
    root = ROOT
    build = root/'build'
    build.mkdir(exist_ok=True)
    def tool(name):
        local = root/'.tools/cc65/usr/bin'/name
        path = Path(toolchain)/name if toolchain else (str(local) if local.exists() else shutil.which(name))
        if not path:
            raise SystemExit(f'{name} not found. Install cc65 or pass --toolchain DIRECTORY.')
        return str(path)
    lines = ['; Generated from host/ab64/tokens.py; do not edit.', 'keyword_table:']
    for index, keyword in enumerate(KEYWORDS):
        if keyword == 'π':
            continue
        lines.append('.byte '+str(len(keyword))+','+','.join(str(c) for c in keyword.encode('ascii'))+','+str(32+index))
    lines.append('.byte 0')
    (root/'src/keywords.inc').write_text('\n'.join(lines)+'\n')
    subprocess.run([tool('ca65'), '-I', str(root/'src'), '-g', '-l', str(build/'assembly-basic.lst'),
                    '-o', str(build/'assembly-basic.o'), str(root/'src/main.s')], check=True)
    subprocess.run([tool('ld65'), '-C', str(root/'src/cart.cfg'), '-m', str(build/'assembly-basic.map'),
                    '-Ln', str(build/'assembly-basic.lbl'), '-o', str(build/'assembly-basic.bin'),
                    str(build/'assembly-basic.o')], check=True)
    labels = {}
    for line in (build/'assembly-basic.lbl').read_text().splitlines():
        match = re.match(r'al ([0-9A-Fa-f]+) \.(.+)', line)
        if match:
            labels[match[2]] = int(match[1], 16)
    rom = (build/'assembly-basic.bin').read_bytes()
    if len(rom) != 65536 or any(rom[bank*8192+4:bank*8192+9] != bytes.fromhex('c3c2cd3830') for bank in range(8)):
        raise SystemExit('invalid Magic Desk size/header')
    gateway = labels['__GATEWAY_SIZE__']
    service_gateway = labels['__SERVICE_GATEWAY_SIZE__']
    services = labels['__SERVICES_SIZE__']
    runtime = labels['__RUNTIME_SIZE__']
    compiler = labels['__COMPILER_SIZE__']
    if gateway > 768 or service_gateway > 204 or runtime > 7162 or compiler > 6144:
        raise SystemExit('RAM budget exceeded')
    for name, bank, size in (('runtime', 2, runtime), ('compiler', 1, compiler)):
        start = labels[f'__{name.upper()}_LOAD__'] - 0x8000
        assert 9 <= start and start+size <= 8192
        (build/f'assembly-basic.bin.{name}').write_bytes(rom[bank*8192+start:bank*8192+start+size])
    # Classic Magic Desk, CRT type 19: GAME high, EXROM low, eight 8-KiB banks.
    header = b'C64 CARTRIDGE   '+struct.pack('>IHHBB', 64, 0x100, 19, 0, 1)+bytes(6)+b'ASSEMBLY BASIC'.ljust(32, b'\0')
    packets = [b'CHIP'+struct.pack('>IHHHH', 8208, 0, bank, 0x8000, 8192)+rom[bank*8192:(bank+1)*8192] for bank in range(8)]
    (build/'assembly-basic.crt').write_bytes(header+b''.join(packets))
    segments = {}
    for line in (build/'assembly-basic.map').read_text().splitlines():
        match = re.match(r'\s+(\w+)\s+Offs=[0-9A-F]+\s+Size=([0-9A-F]+)', line)
        if match:
            segments[match[1]] = int(match[2], 16)
    banks = []
    for bank, role in enumerate(BANK_ROLES):
        names = ('HEADER', 'COMMAND', 'GATEWAY', 'SERVICE_GATEWAY') if bank == 0 else (f'HEADER{bank}',) + (('COMPILER',) if bank == 1 else ('RUNTIME', 'SERVICES') if bank == 2 else ())
        used = sum(segments[name] for name in names)
        banks.append({'bank': bank, 'offset': bank*8192, 'window': [0x8000, 0xa000],
                      'role': role, 'used_bytes': used, 'spare_bytes': 8192-used,
                      'reserved': bank >= 3})
    used = sum(bank['used_bytes'] for bank in banks)
    report = {'rom_bytes': len(rom), 'rom_sha256': hashlib.sha256(rom).hexdigest(),
              'cartridge_type': 19, 'cartridge_format': 'classic Magic Desk', 'bank_bytes': 8192,
              'bank_register': 0xde00, 'banks': banks, 'runtime_abi': 7,
              'runtime_run_address': 0xe400, 'runtime_used_bytes': runtime,
              'runtime_rom_bytes': runtime, 'runtime_image_encoding': 'raw', 'runtime_budget_bytes': 7162,
              'gateway_used_bytes': gateway, 'gateway_budget_bytes': 768, 'workspace_bytes': 3072,
              'service_gateway_run_address': 0x334, 'service_gateway_used_bytes': service_gateway,
              'service_gateway_budget_bytes': 204,
              'services_bank': 2, 'services_rom_address': labels['__SERVICES_LOAD__'],
              'services_rom_bytes': services,
              'arena_spans': [[0x2c00, 0xd000], [0xe000, 0xe400]], 'arena_raw_bytes': 43008,
              'compiler_run_address': 0x1400, 'compiler_used_bytes': compiler,
              'compiler_rom_bytes': compiler, 'compiler_image_encoding': 'raw', 'compiler_budget_bytes': 6144,
              'segments': segments, 'rom_used_bytes': used, 'rom_spare_bytes': 65536-used}
    (build/'size-report.json').write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps(report, indent=2))
    return labels


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--toolchain', default=os.environ.get('CC65_BIN'))
    build(parser.parse_args().toolchain)
