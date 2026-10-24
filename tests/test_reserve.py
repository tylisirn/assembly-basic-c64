"""User RAM reservations and the Void Runner code-overwrite regression."""
from pathlib import Path
import unittest
from machine import Machine
from ab64.cli import text_program
from ab64.container import dumps, loads

ROOT = Path(__file__).resolve().parents[1]
REGIONS = ((0x3c00, 0x3e00), (0xc000, 0xc300))


class ReserveTests(unittest.TestCase):
    def command(self, m, text):
        start = len(m.output)
        m.input.extend(text.encode('latin-1') + b'\r')
        m.pump(40000000)
        return bytes(m.output[start:]).decode('latin-1')

    def free_blocks(self, m):
        p = m.state('free')
        result = []
        while p:
            self.assertNotIn(p, [lo for lo, hi in result], 'free-list cycle')
            result.append((p, p + m.word(p)))
            p = m.word(p + 2)
        return result

    def test_reservations_exclude_user_bytes_from_allocator_and_collector(self):
        m = Machine().boot()
        m.command('RESERVE $3C00,$200');m.command('RESERVE $C000,$300')
        for lo, hi in REGIONS:
            m.memory.ram[lo:hi] = bytes([0xff]) * (hi - lo)
        for number in range(1, 161):
            self.assertNotIn('?', m.command(f'{number} VARIABLE{number}={number}'))
        m.command('200 FOR I=1 TO 50:A$=A$+"X":NEXT I:PRINT LEN(A$);FRE(0)')
        self.assertNotIn('?', self.command(m, 'RUN'))
        self.assertNotIn('?', self.command(m, 'CLEAN'))
        for lo, hi in REGIONS:
            self.assertEqual(m.memory.ram[lo:hi], bytes([0xff]) * (hi - lo))
            for start, end in self.free_blocks(m):
                self.assertFalse(start < hi and end > lo)
        m.command('SAVE "RESERVED"')
        m.command('NEW')
        self.assertEqual(sum(end - start for start, end in self.free_blocks(m)), 43008)
        self.assertNotIn('?', self.command(m, 'LOAD "RESERVED"'))
        # V2 source persists the reservation metadata even for direct declarations.
        self.assertEqual(m.memory.ram[0xbd2], 4)

    def test_boundaries_repeats_conflicts_and_new(self):
        m = Machine().boot()
        for command in ('RESERVE $2C00,$100', 'RESERVE $CF00,$100',
                        'RESERVE $E000,$400', 'RESERVE $2C00,$100'):
            self.assertNotIn('?', m.command(command), command)
        before = self.free_blocks(m)
        for command in ('RESERVE $CFFF,$100', 'RESERVE $C000,0',
                        'RESERVE $C000,1', 'RESERVE $D000,$100',
                        'RESERVE $CF00,$200', 'RESERVE $E300,$200',
                        'RESERVE $FF00,$100', 'RESERVE $1400,$100',
                        'RESERVE $2C00,$200'):
            self.assertIn('?', m.command(command), command)
            self.assertEqual(self.free_blocks(m), before, command)
        m.command('10 PRINT 7')
        self.assertIn('?', m.command('RESERVE $2D00,$100'))  # live anchor slab
        self.assertEqual(m.command('RUN').split('\r')[0], ' 7 ')
        m.command('NEW')
        self.assertEqual(m.memory.ram[0xbd2], 0)
        self.assertEqual(sum(end - start for start, end in self.free_blocks(m)), 43008)

    def test_table_limit_and_declaration_scope(self):
        m = Machine().boot()
        for page in range(0x40, 0x50, 2):
            self.assertNotIn('?', m.command(f'RESERVE ${page:02X}00,$100'))
        before = self.free_blocks(m)
        self.assertIn('?OUT OF MEMORY', m.command('RESERVE $5000,$100'))
        self.assertEqual(self.free_blocks(m), before)
        self.assertNotIn('?', m.command('RESERVE $4000,$100'))
        m.command('NEW')
        self.assertIn('?SYNTAX ERROR', m.command('10 IF 0 THEN RESERVE $C000,$100'))
        self.assertEqual(m.memory.ram[0xbd2], 0)
        self.assertIn('RESERVE', m.command('LIST'))

    def test_source_load_accepts_empty_string_and_data_text(self):
        m = Machine().boot()
        source = '10 A$="":IF A$="" THEN PRINT "EMPTY"\n20 DATA "":READ B$:PRINT LEN(B$)\n'
        m.files['EMPTY'] = dumps(*text_program(source))
        self.assertNotIn('?', m.command('LOAD "EMPTY"'))
        self.assertIn('EMPTY\r 0 ', self.command(m, 'RUN'))
        m.command('SAVE "COPY"')
        self.assertEqual(dumps(*loads(bytes(m.files['COPY']))), dumps(*loads(bytes(m.files['EMPTY']))))

    def test_voidrunner_paste_and_source_load_reach_native_gameplay(self):
        source = (ROOT / 'examples/voidrunner.bas').read_text(encoding='latin-1')
        names, lines = text_program(source)
        for method in ('paste', 'load'):
            with self.subTest(method=method):
                m = Machine().boot()
                if method == 'paste':
                    for row in source.splitlines():
                        self.assertNotIn('?', m.command(row), row)
                else:
                    m.files['VOID'] = dumps(names, lines)
                    m.input.extend(b'LOAD "VOID"\r');m.pump(40000000)
                    self.assertEqual(m.errors, [])
                anchor = m.state('head')
                bodies = []
                while anchor != m.labels['run_end']:
                    payload = m.word(anchor + 5)
                    lo, hi = payload - 2, payload - 2 + m.word(payload - 2)
                    for start, end in REGIONS:
                        self.assertFalse(lo < end and hi > start)
                    bodies.append((lo, hi, bytes(m.memory.ram[lo:hi])))
                    anchor = m.word(hi - 2)
                # Released joystick, then keyboard SPACE at the title prompt.
                m.memory.ram[0xdc00] = 255
                m.input.extend(b'RUN\r ')
                calls = 0
                for _ in range(5000000):
                    if m.cpu.pc == 0xc000:
                        calls += 1
                        if calls == 12:
                            break
                    if not m.step():
                        self.fail(f'Game stopped early: {bytes(m.output[-120:])!r}')
                else:
                    self.fail(f'Game never reached twelve native frames: ${m.cpu.pc:04X}')
                self.assertEqual(m.errors, [])
                self.assertIn(b'score:000000', bytes(m.output).lower())
                self.assertEqual(m.memory.ram[0xc21b], 11)
                self.assertEqual(m.memory.ram[0xc000:0xc003], bytes((238, 27, 194)))
                self.assertTrue(any(m.memory.ram[0x3c00:0x3d80]))
                for lo, hi, code in bodies:
                    self.assertEqual(bytes(m.memory.ram[lo:hi]), code, f'Overwritten body ${lo:04X}')
                # Exercise both reported game-over triggers, rather than stopping
                # the test before the formerly mis-tokenized TAB (11) executes.
                if method == 'load':
                    m.input.extend(b'q')
                else:
                    name = m.state('name_head')
                    while name:
                        spelling = bytes(m.memory.ram[name+9:name+9+m.memory.ram[name+8]])
                        if spelling == b'LI':
                            m.memory.ram[name+4:name+6] = b'\0\0'
                            break
                        name = m.word(name)
                    self.assertNotEqual(name, 0)
                for _ in range(1000000):
                    if m.word(m.state('line')+3) == 7090:
                        break
                    if not m.step():
                        self.fail(f'Game-over stopped early: {bytes(m.output[-120:])!r}')
                else:
                    self.fail('Game-over did not reach its fire/space wait')
                self.assertEqual(m.errors, [])
                self.assertIn(b'mission ended', bytes(m.output).lower())
                self.assertIn(b'high  ', bytes(m.output).lower())
                for lo, hi, code in bodies:
                    self.assertEqual(bytes(m.memory.ram[lo:hi]), code, f'Overwritten body ${lo:04X}')
                # Abort at the next BASIC poll, then collect the arbitrary ML
                # bytes and rebuild the stopped program under the same bounds.
                m.memory.ram[0x77] = 1
                m.pump()
                self.assertNotIn('?', self.command(m, 'PRINT FRE(0)'))
                listing = self.command(m, 'LIST')
                cleaned = self.command(m, 'CLEAN')
                if '?' in cleaned:
                    self.assertIn('?OUT OF MEMORY', cleaned)
                self.assertEqual(self.command(m, 'LIST'), listing)
                self.assertEqual(m.memory.ram[0xc000:0xc003], bytes((238, 27, 194)))
