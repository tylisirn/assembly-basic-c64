"""Captured Void Runner heap and boundary/automatic-collection regressions."""
import hashlib
import json
from pathlib import Path
import unittest
import zlib
from machine import Machine

ROOT = Path(__file__).resolve().parents[1]
SPANS = ((0x2c00, 0xd000), (0xe000, 0xe400))


def word(ram, p):
    return ram[p] | ram[p + 1] << 8


def store(ram, p, value):
    ram[p:p + 2] = value.to_bytes(2, 'little')


def free_blocks(ram):
    result = []
    seen = set()
    p = word(ram, 0xb00)
    while p:
        if p in seen:
            raise AssertionError('free-list cycle')
        seen.add(p)
        result.append([p, word(ram, p)])
        p = word(ram, p + 2)
    return result


def collect(m, limit=600000):
    ram = m.memory.ram
    ram[0:2] = b'\x2f\x35'
    m.cpu.pc = m.labels['collect']
    m.cpu.sp = 0xff
    m.cpu.stPushWord(0x01ff)  # RTS returns to the test sentinel at $0200.
    cycles = m.cpu.processorCycles
    for count in range(limit):
        if m.cpu.pc == 0x0200:
            assert m.cpu.sp == 0xff
            return count, m.cpu.processorCycles - cycles
        m.cpu.step()
    raise AssertionError(f'Collection exceeded {limit} instructions at ${m.cpu.pc:04X}')


class CollectionTests(unittest.TestCase):
    def test_captured_voidrunner_heap_matches_completed_old_collector(self):
        metadata = json.loads((ROOT/'tests/fixtures/voidrunner-heap.json').read_text())
        before = zlib.decompress((ROOT/'tests/fixtures/voidrunner-heap.zlib').read_bytes())
        self.assertEqual(hashlib.sha256(before).hexdigest(), metadata['fixture_ram_sha256'])
        m = Machine()
        m.memory.ram[:] = before
        runtime = (ROOT/'build/assembly-basic.bin.runtime').read_bytes()
        m.memory.ram[0xe400:0xe400 + len(runtime)] = runtime
        count, cycles = collect(m)
        self.assertLess(cycles, 2000000)
        self.assertEqual(free_blocks(m.memory.ram), metadata['expected_free_blocks'])
        free = {p for p, _ in metadata['expected_free_blocks']}
        physical = 0
        for lo, hi in ((0x2c00, 0x3c00), (0x3e00, 0xc000),
                       (0xc300, 0xd000), (0xe000, 0xe400)):
            p = lo
            while p < hi:
                size = word(m.memory.ram, p)
                self.assertGreaterEqual(size, 4)
                if p not in free:
                    self.assertEqual(bytes(m.memory.ram[p:p + size]), before[p:p + size],
                                     f'Live allocation changed at ${p:04X}')
                p += size
                physical += 1
            self.assertEqual(p, hi)
        for lo, hi in ((0x3c00, 0x3e00), (0xc000, 0xc300)):
            self.assertEqual(bytes(m.memory.ram[lo:hi]), before[lo:hi])
        self.assertEqual(sum(size for _, size in metadata['expected_free_blocks']), 5651)
        self.assertGreater(physical, 0)

    def test_shared_low_bytes_and_payload_crossing_window_boundary(self):
        m = Machine().boot()
        ram = m.memory.ram
        ram[2:0x79] = bytes(0x77)
        ram[0xb00:0xc00] = bytes(0x100)
        starts = [0x3000 + page * 0x100 for page in range(9)] + [0x3ffe, 0xe000]
        live = {0x3000, 0x3200, 0x3700, 0x3800, 0x3ffe, 0xe000}
        free = []
        for lo, hi in SPANS:
            p = lo
            for header in [start for start in starts if lo <= start < hi]:
                if p < header:
                    store(ram, p, header - p)
                    free.append(p)
                store(ram, header, 4)
                ram[header + 2:header + 4] = b'OK'
                p = header + 4
            if p < hi:
                store(ram, p, hi - p)
                free.append(p)
        store(ram, 0xb00, free[0])
        for index, p in enumerate(free):
            store(ram, p + 2, free[index + 1] if index + 1 < len(free) else 0)
        ram[0x40] = len(live)
        for index, header in enumerate(sorted(live)):
            ram[0xf00 + 4 * index:0xf04 + 4 * index] = bytes((1, 2)) + (header + 2).to_bytes(2, 'little')
        collect(m)
        released = free_blocks(ram)
        for header in live:
            self.assertEqual(ram[header:header + 4], b'\x04\x00OK')
            self.assertFalse(any(p <= header < p + size for p, size in released))
        for header in set(starts) - live:
            self.assertTrue(any(p <= header < p + size for p, size in released))
        self.assertEqual(sum(size for _, size in released), 43008 - 4 * len(live))

    def test_empty_free_list_and_full_word_allocation_sizes(self):
        m = Machine().boot()
        ram = m.memory.ram
        ram[2:0x79] = bytes(0x77)
        ram[0xb00:0xc00] = bytes(0x100)
        for lo, hi in SPANS:
            store(ram, lo, hi - lo)
        store(ram, 0x39, 0x2c02)  # helper string root
        store(ram, 0x36, 0xe002)  # helper temporary root
        collect(m)
        self.assertEqual(free_blocks(ram), [])
        self.assertEqual(word(ram, 0x2c00), 0xa400)
        store(ram, 0x39, 0)
        store(ram, 0x36, 0)
        collect(m)
        self.assertEqual(free_blocks(ram), [[0x2c00, 0xa400], [0xe000, 0x400]])

    def test_automatic_score_string_collection_keeps_arrays_and_functions(self):
        m = Machine().boot()
        for line in ('10 DIM S$(2):S$(1)="KEPT":DEF FN F(X)=X+1',
                     '20 FOR I=1 TO 1200',
                     '30 A$="score:"+RIGHT$("000000"+MID$(STR$(I),2),6)',
                     '40 NEXT I:PRINT A$;S$(1);FN F(2):PRINT FRE(0)'):
            self.assertNotIn('?', m.command(line))
        m.input.extend(b'RUN\r')
        collections = 0
        for _ in range(12000000):
            if m.cpu.pc == m.labels['collect']:
                collections += 1
            if not m.step():
                break
        else:
            self.fail(f'Score workload did not finish at ${m.cpu.pc:04X}')
        self.assertEqual(m.errors, [])
        self.assertIn(b'score:001200KEPT 3 ', m.output)
        self.assertGreaterEqual(collections, 2)  # allocation failure plus explicit FRE
