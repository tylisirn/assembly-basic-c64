#!/usr/bin/env python3
"""Reproducible ca65/ld65 build, CRT packaging and section-budget report."""
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
from lz import compress, decompress

def build(toolchain=None):
    root = ROOT
    build = root/'build'
    build.mkdir(exist_ok=True)
    def tool(n):
        local=ROOT/'.tools/cc65/usr/bin'/n
        p = Path(toolchain)/n if toolchain else (str(local) if local.exists() else shutil.which(n))
        if not p:
            raise SystemExit(f'{n} not found. Install cc65 or pass --toolchain DIRECTORY.')
        return str(p)
    lines = ['; Generated from host/ab64/tokens.py; do not edit.', 'keyword_table:']
    for i,k in enumerate(KEYWORDS):
        if k == 'π':
            continue
        lines.append('.byte '+str(len(k))+','+','.join(str(c) for c in k.encode('ascii'))+','+str(32+i))
    lines.append('.byte 0')
    (root/'src/keywords.inc').write_text('\n'.join(lines)+'\n')
    (build/'runtime.lz').write_bytes(b'')
    (build/'compiler0.lz').write_bytes(b'')
    (build/'compiler.lz').write_bytes(b'')
    subprocess.run([tool('ca65'),'-I',str(root/'src'),'--bin-include-dir',str(build),'-g','-l',str(build/'assembly-basic.lst'),'-o',str(build/'assembly-basic.o'),str(root/'src/main.s')],check=True)
    subprocess.run([tool('ld65'),'-C',str(root/'src/cart.cfg'),'-m',str(build/'assembly-basic.map'),'-Ln',str(build/'assembly-basic.lbl'),'-o',str(build/'assembly-basic.bin'),str(build/'assembly-basic.o')],check=True)
    raw_runtime=(build/'assembly-basic.bin.runtime').read_bytes()
    packed=compress(raw_runtime)
    assert decompress(packed,len(raw_runtime))==raw_runtime
    (build/'runtime.lz').write_bytes(packed)
    raw_compiler=(build/'assembly-basic.bin.compiler').read_bytes()
    packed_compiler=compress(raw_compiler)
    assert decompress(packed_compiler,len(raw_compiler))==raw_compiler
    # Fill the first bank after command/gateway code; put the remainder in bank 1.
    # These load addresses are identical in the empty and final packed links.
    first_labels = (build/'assembly-basic.lbl').read_text()
    def first_label(name):
        match = re.search(r'al ([0-9A-Fa-f]+) \.' + name + r'$', first_labels, re.M)
        return int(match[1], 16)
    first_capacity = 0xa000 - first_label('__GATEWAY_LOAD__') - first_label('__GATEWAY_SIZE__')
    first_size = min(first_capacity, len(packed_compiler))
    (build/'compiler0.lz').write_bytes(packed_compiler[:first_size])
    (build/'compiler.lz').write_bytes(packed_compiler[first_size:])
    subprocess.run([tool('ca65'),'-I',str(root/'src'),'--bin-include-dir',str(build),'-g','-l',str(build/'assembly-basic.lst'),'-o',str(build/'assembly-basic.o'),str(root/'src/main.s')],check=True)
    subprocess.run([tool('ld65'),'-C',str(root/'src/cart.cfg'),'-m',str(build/'assembly-basic.map'),'-Ln',str(build/'assembly-basic.lbl'),'-o',str(build/'assembly-basic.bin'),str(build/'assembly-basic.o')],check=True)
    assert (build/'assembly-basic.bin.runtime').read_bytes()==raw_runtime
    assert (build/'assembly-basic.bin.compiler').read_bytes()==raw_compiler
    rom = (build/'assembly-basic.bin').read_bytes()
    if len(rom) != 16384 or rom[4:9] != bytes.fromhex('c3c2cd3830'):
        raise SystemExit('invalid cartridge size/header')
    labels = {}
    for l in (build/'assembly-basic.lbl').read_text().splitlines():
        m = re.match(r'al ([0-9A-Fa-f]+) \.(.+)',l)
        if m:
            labels[m[2]] = int(m[1],16)
    gateway = labels['__GATEWAY_SIZE__']
    runtime = labels['__RUNTIME_SIZE__']
    if gateway > 768 or runtime > 7162 or len(raw_compiler) > 6144:
        raise SystemExit('RAM budget exceeded')
    # VICE 3.7.1's generic loader treats a second packet as Ultimax ROM. Use one
    # contiguous 16-KiB packet for the normal $8000-$BFFF cartridge instead.
    header = b'C64 CARTRIDGE   '+struct.pack('>IHHBB',64,0x100,0,0,0)+bytes(6)+b'ASSEMBLY BASIC'.ljust(32,b'\0')
    crt = header+b'CHIP'+struct.pack('>IHHHH',16400,0,0,0x8000,16384)+rom
    (build/'assembly-basic.crt').write_bytes(crt)
    report = {'rom_bytes':len(rom),'rom_sha256':hashlib.sha256(rom).hexdigest(),'runtime_run_address':0xe400,'runtime_used_bytes':runtime,'runtime_packed_bytes':len(packed),'runtime_budget_bytes':7162,'gateway_used_bytes':gateway,'gateway_budget_bytes':768,'workspace_bytes':3072,'arena_spans':[[0x2c00,0xd000],[0xe000,0xe400]],'arena_raw_bytes':43008,'compiler_run_address':0x1400,'compiler_used_bytes':len(raw_compiler),'compiler_packed_bytes':len(packed_compiler),'compiler_budget_bytes':6144}
    segments={}
    for line in (build/'assembly-basic.map').read_text().splitlines():
        m=re.match(r'\s+(\w+)\s+Offs=[0-9A-F]+\s+Size=([0-9A-F]+)',line)
        if m:segments[m[1]]=int(m[2],16)
    report['segments']=segments
    report['rom_used_bytes']=sum(v for k,v in segments.items() if k not in ('RUNTIME','COMPILER'))
    report['rom_spare_bytes']=16384-report['rom_used_bytes']
    report['runtime_abi']=3
    (build/'size-report.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
    return labels

if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('--toolchain',default=os.environ.get('CC65_BIN'))
    build(p.parse_args().toolchain)
