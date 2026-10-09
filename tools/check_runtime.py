#!/usr/bin/env python3
"""Check the runtime's static instructions and hidden-ROM dependency closure."""
import re
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'.tools/py65'))
from py65.devices.mpu6502 import MPU
from py65.disassembler import Disassembler


def check():
    labels={}
    for line in (ROOT/'build/assembly-basic.lbl').read_text().splitlines():
        m=re.match(r'al (\w+) \.(.+)',line)
        if m:labels[m[2]]=int(m[1],16)
    raw=(ROOT/'build/assembly-basic.bin.runtime').read_bytes()
    base=labels['__RUNTIME_RUN__'];end=base+len(raw)
    memory=bytearray(65536);memory[base:end]=raw
    cpu=MPU(memory=memory);dis=Disassembler(cpu)
    data={labels[k]:n for k,n in [('gc_bits',8),('powers_lo',5),('powers_hi',5),('runtime_stamp',5),('clock_low',3),('clock_mid',3),('clock_high',3)]}
    gateways={labels[k] for k in ('kernal_gate','enter_ready','sys_gateway','usr_gateway','file_entry')}
    dynamic={labels['fn_dispatch']}
    p=base;count=0
    while p<end:
        if p in data:p+=data[p];continue
        n,text=dis.instruction_at(p)
        if text.startswith('???'):raise AssertionError(f'undocumented opcode at ${p:04X}')
        op=memory[p]
        if n==3 and op in (0x20,0x4c):
            target=memory[p+1]|memory[p+2]<<8
            if p not in dynamic and not (base<=target<end or target in gateways):
                raise AssertionError(f'helper calls outside its closure at ${p:04X}: {text}')
        if n==3 and op not in (0x20,0x4c,0x6c):
            target=memory[p+1]|memory[p+2]<<8
            if 0x8000<=target<0xc000:
                raise AssertionError(f'helper references hidden cartridge at ${p:04X}: {text}')
        p+=n;count+=1
    assert p==end
    print(f'Runtime closure: {count} documented instructions; all static calls remain in RAM or declared gateways.')
    return count

if __name__=='__main__':check()
