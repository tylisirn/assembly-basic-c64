#!/usr/bin/env python3
"""Replay captured collector inputs with the current assembled RAM runtime."""
import hashlib
import json
from pathlib import Path
import sys
import zlib

ROOT = Path(__file__).resolve().parents[1]
for path in ('host', '.tools/py65'):
    sys.path.insert(0, str(ROOT/path))
from ab64.emulator import Machine


def measure_collection():
    fixture = ROOT/'tests/fixtures'
    metadata = json.loads((fixture/'voidrunner-heap.json').read_text())
    captured = zlib.decompress((fixture/'voidrunner-heap.zlib').read_bytes())
    assert hashlib.sha256(captured).hexdigest() == metadata['fixture_ram_sha256']
    m = Machine()
    m.memory.ram[:] = captured
    runtime = (ROOT/'build/assembly-basic.bin.runtime').read_bytes()
    base = m.labels['__RUNTIME_RUN__']
    m.memory.ram[base:base + len(runtime)] = runtime
    m.memory.ram[0:2] = b'\x2f\x35'
    m.cpu.pc = m.labels['collect']
    m.cpu.sp = 0xff
    m.cpu.stPushWord(0x01ff)
    start_cycles = m.cpu.processorCycles
    for instructions in range(600000):
        if m.cpu.pc == 0x0200:
            break
        m.cpu.step()
    else:
        raise AssertionError('Captured heap collection exceeded 600,000 instructions')
    assert m.cpu.sp == 0xff
    free = []
    seen = set()
    pointer = m.state('free')
    while pointer:
        assert pointer not in seen, 'Free-list cycle'
        seen.add(pointer)
        free.append([pointer, m.word(pointer)])
        pointer = m.word(pointer + 2)
    assert free == metadata['expected_free_blocks'], 'Captured heap result changed'
    result = {
        'rom_sha256': hashlib.sha256((ROOT/'build/assembly-basic.bin').read_bytes()).hexdigest(),
        'environment': 'instruction-level py65; no IRQ/VIC timing',
        'captured_physical_blocks': metadata['physical_blocks'],
        'initial_free_blocks': metadata['initial_free_blocks'],
        'old_remaining_instructions': metadata['baseline_remaining_instructions'],
        'old_remaining_cpu_cycles': metadata['baseline_remaining_cpu_cycles'],
        'new_full_instructions': instructions,
        'new_full_cpu_cycles': m.cpu.processorCycles - start_cycles,
        'final_free_blocks': len(free),
        'final_free_bytes': sum(size for _, size in free),
    }
    destination = ROOT/'docs/implementation/voidrunner-collection.json'
    destination.write_text(json.dumps(result, indent=2) + '\n')
    print(destination)
    return result


if __name__ == '__main__':
    measure_collection()
