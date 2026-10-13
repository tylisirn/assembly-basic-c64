#!/usr/bin/env python3
"""Check resident/runtime and banked-service dependency closures."""
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
    # Bank-2 services execute with ROM visible. RAM helper calls must carry an
    # explicit bank_call descriptor; ordinary calls stay in this bank or gates.
    rom=(ROOT/'build/assembly-basic.bin').read_bytes()
    service_base=labels['__SERVICES_LOAD__'];service_end=service_base+labels['__SERVICES_SIZE__']
    memory[service_base:service_end]=rom[2*8192+service_base-0x8000:2*8192+service_end-0x8000]
    service_gates={labels[k] for k in ('bank_call','read_ram','kernal_gate','file_entry')}
    p=service_base;service_count=0
    while p<service_end:
        n,text=dis.instruction_at(p)
        if text.startswith('???'):raise AssertionError(f'undocumented service opcode at ${p:04X}')
        op=memory[p]
        if n==3 and op in (0x20,0x4c):
            target=memory[p+1]|memory[p+2]<<8
            if not (service_base<=target<service_end or target in service_gates):
                raise AssertionError(f'ROM service calls outside its bank/gateways at ${p:04X}: {text}')
            if target==labels['bank_call']:
                assert op==0x20 and p+7<=service_end, 'Truncated service call descriptor'
                bank,mode=memory[p+3:p+5]
                callback=memory[p+5]|memory[p+6]<<8
                assert bank==0xff and mode==5 and base<=callback<end, 'Invalid RAM callback descriptor'
                n+=4
        if op in (0xa1,0xb1):
            raise AssertionError(f'ROM service reads an unstaged indirect RAM pointer at ${p:04X}')
        p+=n;service_count+=1
    assert p==service_end
    stub_base=labels['__SERVICE_GATEWAY_RUN__'];stub_end=stub_base+labels['__SERVICE_GATEWAY_SIZE__']
    stub_load=labels['__SERVICE_GATEWAY_LOAD__']-0x8000
    memory[stub_base:stub_end]=rom[stub_load:stub_load+stub_end-stub_base]
    p=stub_base;stub_count=0
    while p<stub_end:
        n,text=dis.instruction_at(p)
        if text.startswith('???'):raise AssertionError(f'undocumented service stub opcode at ${p:04X}')
        if memory[p]==0x20:
            target=memory[p+1]|memory[p+2]<<8
            assert target==labels['bank_call'] and p+7<=stub_end, 'Invalid service stub call'
            bank,mode=memory[p+3:p+5]
            service=memory[p+5]|memory[p+6]<<8
            assert bank==2 and mode==7 and service_base<=service<service_end, 'Invalid ROM service descriptor'
            n+=4
        p+=n;stub_count+=1
    assert p==stub_end
    print(f'Runtime closure: {count} documented instructions; ROM services: {service_count}; entry stubs: {stub_count}; all static calls use their declared maps/gateways.')
    return count

if __name__=='__main__':check()
