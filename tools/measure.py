#!/usr/bin/env python3
"""Record instruction-level harness measurements, never hardware timing claims."""
import json
import hashlib
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1]
for p in ('host','.tools/py65'):sys.path.insert(0,str(ROOT/p))
from ab64.emulator import Machine
from measure_collection import measure_collection

def measure():
    m=Machine().boot()
    report={'rom_sha256':hashlib.sha256((ROOT/'build/assembly-basic.bin').read_bytes()).hexdigest(),
            'environment':'py65 1.2.0, deterministic KERNAL stubs; no VIC/IEC timing',
            'cold_start_instructions':m.steps,'workloads':{}}
    for name,program in {
        'integer_loop':['10 A=0:FOR I=1 TO 100:A=A+I:NEXT I:PRINT A'],
        'strings_arrays':['10 DIM A(2,3),S$(2):A(1,2)=123:S$(1)="ROOT"',
                          '20 DEF FN DOUBLE(X)=X*2:PRINT FN DOUBLE(A(1,2));S$(1)'],
        'shadow_address':['10 V=$D000:POKE V+$21,1:PRINT V;PEEK(V+33)'],
    }.items():
        m.command('NEW');before=m.steps
        for row in program:m.command(row)
        compile_steps=m.steps-before
        lines=[];anchor=m.state('head')
        while anchor!=m.labels['run_end']:
            payload=m.word(anchor+5);size=m.word(payload-2);tokens=m.memory.ram[payload]
            lines.append({'line':m.word(anchor+3),'token_bytes':tokens,
                          'native_bytes':size-3-tokens,'payload_physical_bytes':size})
            anchor=m.word(payload-2+size-2)
        before=m.steps;output=m.command('RUN')
        if '?' in output:raise AssertionError(output)
        report['workloads'][name]={'entry_instructions':compile_steps,'run_instructions':m.steps-before,
                                  'output':output,'lines':lines}
    # A repeatable capacity scenario, not a promise for arbitrary BASIC source.
    m.command('NEW');accepted=0
    for number in range(1,2001):
        before_errors=len(m.errors)
        output=m.command(f'{number} A=A+1')
        if len(m.errors)!=before_errors:break
        accepted+=1
    else:raise AssertionError('capacity probe did not reach an allocation limit')
    free=0;pointer=m.state('free');seen=set()
    while pointer:
        if pointer in seen:raise AssertionError('free-list cycle')
        seen.add(pointer);free+=m.word(pointer);pointer=m.word(pointer+2)
    report['capacity_scenario']={'source_template':'<number> A=A+1',
        'accepted_lines':accepted,'first_rejected_line':number,
        'remaining_free_physical_bytes':free,'failure':output,
        'note':'Cold NEW, one scalar; common-span anchor exhaustion and fragmentation can limit capacity before all raw bytes are used.'}
    destination=ROOT/'docs/measurements.json'
    destination.write_text(json.dumps(report,indent=2)+'\n')
    print(destination)
    measure_collection()

if __name__=='__main__':measure()
