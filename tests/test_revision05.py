"""Revision 0.5 behavior exercised through the actual cartridge and native code."""
import random
import re
import unittest
from pathlib import Path
from machine import Machine
from ab64.tokens import CODES, Names, tokenize, listing
from ab64.container import dumps, loads


def signed(value):
    return (value + 32768) % 65536 - 32768


class Revision05Tests(unittest.TestCase):
    def setUp(self):
        self.m = Machine().boot()

    def result(self, source):
        return self.m.command('PRINT ' + source).split('\r')[0]

    def slab_counts(self):
        counts = []
        p = self.m.state('slab')
        while p:
            counts.append(self.m.memory.ram[p + 2])
            p = self.m.word(p)
        return counts

    def test_resident_compiler_image_is_reserved_and_survives_collection(self):
        m = self.m
        raw = (Path(__file__).resolve().parents[1] / 'build/assembly-basic.bin.compiler').read_bytes()
        start = m.labels['__COMPILER_RUN__']
        self.assertEqual(start, 0x1400)
        self.assertLessEqual(len(raw), 6144)
        self.assertEqual(bytes(m.memory.ram[start:start + len(raw)]), raw)
        m.command('10 PRINT FRE(0)');m.command('RUN');m.command('CLEAN')
        self.assertGreaterEqual(m.state('head'), 0x2c00)
        self.assertEqual(bytes(m.memory.ram[start:start + len(raw)]), raw)

    def test_submission_reports_failure_and_retains_source(self):
        m = self.m
        self.assertEqual(m.command('10 PRINT 7'), '')
        for source in ('20 A=(', '30 PRINT 1.5', '40 PRINT @', '50 PRINT SIN(1)', '60 DATA 1.5'):
            out = m.command(source)
            self.assertIn('?', out)
            self.assertNotIn('READY.', out)
            self.assertIn(source.split()[0] + ' ', m.command('LIST'))
        self.assertEqual(m.command('50'), '')
        self.assertNotIn('50 ', m.command('LIST'))
        self.assertEqual(m.command('10 PRINT 8'), '')
        self.assertEqual(m.command('RUN').split('\r')[0], ' 8 ')

    def test_list_bounds_and_newline(self):
        m = self.m
        for n in (0, 10, 20, 50, 63999):
            m.command(f'{n} PRINT {n}')
        for command, expected in (
            ('LIST', [0, 10, 20, 50, 63999]), ('LIST 10', [10]),
            ('LIST 10-50', [10, 20, 50]), ('LIST 11-49', [20]),
            ('LIST -10', [0, 10]), ('LIST 50-', [50, 63999]),
            ('LIST 63999', [63999]), ('LIST 30', []), ('LIST 50-10', []),
        ):
            out = m.command(command)
            self.assertTrue(out.startswith('\r'), command)
            self.assertEqual([int(n) for n in re.findall(r'(?:^|\r)(\d+) PRINT', out)], expected)
        for command in ('LIST A', 'LIST 10 20', 'LIST 64000', 'LIST --10'):
            self.assertIn('?', m.command(command), command)

    def test_else_branches_nesting_colons_and_line_targets(self):
        m = self.m
        for condition in (0, 1):
            m.command(f'10 IF {condition} THEN PRINT 1:PRINT 2 ELSE PRINT 3:PRINT 4')
            self.assertEqual(m.command('RUN').split('\r\r')[0],
                             ' 1 \r 2 ' if condition else ' 3 \r 4 ')
        cases = (
            ('IF 0 THEN IF 1 THEN PRINT 1 ELSE PRINT 2 ELSE PRINT 3', 3),
            ('IF 1 THEN IF 0 THEN PRINT 1 ELSE PRINT 2 ELSE PRINT 3', 2),
            ('IF 1 THEN IF 1 THEN PRINT 1 ELSE PRINT 2 ELSE PRINT 3', 1),
            ('IF 0 THEN IF 0 THEN PRINT 1 ELSE PRINT 2', None),
            ('IF 1 THEN PRINT 1:ELSE PRINT 2', 1),
        )
        for source, value in cases:
            m.command('10 ' + source)
            out = m.command('RUN')
            self.assertNotIn('?', out, source)
            self.assertEqual(out.split('\r')[0], '' if value is None else f'{value: d} ', source)
        m.command('20 PRINT 2:END');m.command('30 PRINT 3:END')
        for condition, value in ((0, 3), (1, 2)):
            m.command(f'10 IF {condition} THEN 20 ELSE 30')
            self.assertEqual(m.command('RUN').split('\r')[0], f'{value: d} ')
        self.assertIn('?', m.command('10 ELSE PRINT 7'))

    def test_rng_initial_seed_uses_clock_once(self):
        m = self.m
        state = (m.jiffy * 25173 + 13849) & 65535
        self.assertEqual(self.result('RND(0)'), ' 0 ')
        self.assertEqual(self.result('RND(1)'), f'{signed(state): d} ')
        m.jiffy += 99
        state = (state * 25173 + 13849) & 65535
        self.assertEqual(self.result('RND(1)'), f'{signed(state): d} ')

    def test_rng_full_word_reseed_and_repeat(self):
        state = 65535
        for argument in (-1, 1, 1, 1, 1, 1, 1, 1):
            state = (state * 25173 + 13849) & 65535
            self.assertEqual(self.result(f'RND({argument})'), f'{signed(state): d} ')
            self.assertEqual(self.result('RND(0)'), f'{signed(state): d} ')
        first = self.result('RND(-123)')
        self.assertEqual(self.result('RND(-123)'), first)
        self.assertIn('?TYPE MISMATCH', self.m.command('PRINT RND("A")'))

    def test_arithmetic_shifts_precedence_and_checked_counts(self):
        cases = {'1<<15': 32768, '-5>>1': -3, '$8000>>15': 65535,
                 '$FFFF<<1': 65534, '7>>0': 7, '1<<16': 0, '-1>>255': -1,
                 '1+2<<2': 12, '1<<1+2': 8, '8>>1>>1': 2,
                 '1<<2=4': -1, 'NOT 1<<2=4': 0, '-2^2>>1': -2}
        for source, expected in cases.items():
            self.assertEqual(self.result(source), f'{expected: d} ', source)
        for source in ('1<<-1', '1>>256', '1<<"A"'):
            self.assertIn('?', self.m.command('PRINT ' + source))
        m = self.m
        m.command('10 PRINT -5 >> 1;1 << 15')
        self.assertIn('>>', m.command('LIST'));self.assertIn('<<', m.command('LIST'))

    def test_power_of_two_lowering_preserves_division(self):
        m = self.m
        rng = random.Random(5)
        for _ in range(40):
            value = rng.randrange(-32768, 32768)
            power = rng.randrange(15)
            divisor = 1 << power
            quotient = abs(value) // divisor * (-1 if value < 0 else 1)
            self.assertEqual(self.result(f'{value}/{divisor}'), f'{quotient: d} ')
            self.assertEqual(self.result(f'{value}*{divisor}'), f'{signed(value * divisor) if value < 0 else (value * divisor) & 65535: d} ')
        for source, helper in (('A*8', 'shift_left_word'), ('8*A', 'shift_left_word'),
                               ('A/8', 'divide_power_word'), ('A/(8)', 'divide_power_word'),
                               ('(8)*A', 'shift_left_word'), ('A*+(8)', 'shift_left_word'),
                               ('A/$8000', 'divide_negative_power_word')):
            m.command('10 PRINT ' + source)
            p = m.word(m.state('head') + 5)
            native = bytes(m.memory.ram[p + 1 + m.memory.ram[p]:p - 2 + m.word(p - 2)])
            calls = lambda name: b'\x20' + m.labels[name].to_bytes(2, 'little')
            self.assertIn(calls(helper), native)
            self.assertNotIn(calls('multiply_word'), native)
            self.assertNotIn(calls('divide_word'), native)
        for source, expected in (('2*8^2', 128), ('32/2^3', 4), ('2*8+1', 17),
                                 ('8*2^3+1', 65), ('-5/2/2', -1), ('3*8*2', 48),
                                 ('-32768/32768', 1), ('-32767/$8000', 0),
                                 ('32767/$8000', 0)):
            self.assertEqual(self.result(source), f'{expected: d} ', source)

    def test_clean_rebuilds_dense_slabs_symbols_and_refs(self):
        m = self.m
        for n in range(1, 141):
            m.command(f'{n} OLD{n}={n}')
        for n in range(1, 141):
            m.command(str(n))
        for source in ('10 DIM A(2):DEF FN F(X)=X*2:DATA 001',
                       '20 READ S$:A(1)=3:GOSUB 50:IF 0 THEN GOTO 99 ELSE PRINT S$;FN F(A(1))',
                       '30 STOP:PRINT 9:END', '50 PRINT "SUB";:RETURN'):
            self.assertNotIn('?', m.command(source))
        before = m.command('LIST')
        self.assertGreaterEqual(sum(self.slab_counts()), 140)
        self.assertGreater(m.word(0x28), 140)
        self.assertIn('SUB001 6 ', m.command('RUN'))
        m.command('A=9')
        self.assertNotIn('?', m.command('CLEAN'))
        self.assertEqual(m.command('LIST'), before)
        self.assertEqual(self.slab_counts(), [5])  # Four live lines and referenced missing 99.
        self.assertEqual(m.word(0x28), 4)  # A, F, X and S$; old names are gone.
        self.assertIn("?CAN'T CONTINUE", m.command('CONT'))
        self.assertEqual(self.result('A'), ' 0 ')
        self.assertIn('SUB001 6 ', m.command('RUN'))
        m.command('SAVE "DENSE"')
        names, lines = loads(bytes(m.files['DENSE']))
        self.assertEqual(len(names.names), m.word(0x28))
        self.assertEqual(dumps(names, lines), bytes(m.files['DENSE']))
        self.assertNotIn('?', m.command('CLEAN'))
        self.assertEqual(m.command('LIST'), before)

    def test_clean_allocation_failure_rolls_back_and_cleans_transport(self):
        for failure_site in range(1, 8):
            m = Machine().boot()
            m.command('10 A=7:PRINT A');m.command('20 GOTO 10')
            before = m.command('LIST');names = m.word(0x28)
            m.input.extend(b'CLEAN\r')
            start = len(m.output);allocations = 0
            for _ in range(2000000):
                if m.cpu.pc in (m.labels['command_alloc'], m.labels['command_alloc_common']):
                    allocations += 1
                    if allocations == failure_site:
                        m.cpu.a = m.cpu.x = 255
                if not m.step():
                    break
            else:
                self.fail('CLEAN did not finish')
            out = bytes(m.output[start:]).decode('latin-1')
            self.assertGreaterEqual(allocations, failure_site)
            self.assertIn('?OUT OF MEMORY', out, str(failure_site))
            self.assertEqual(m.command('LIST'), before)
            self.assertEqual(m.word(0x28), names)
            self.assertEqual(m.memory.ram[0xb00 + 202], 0)
            self.assertEqual(m.memory.ram[0x65], 0)
            m.command('SAVE "AFTER"')
            self.assertIn('AFTER', m.files)

    def test_clean_failure_reclaims_staged_array_and_function_records(self):
        m = self.m
        m.command('10 DIM A(1):DEF FN F(X)=X:PRINT 7');m.command('20 GOTO 10')
        before = m.command('LIST')
        def free_bytes():
            p = m.state('free'); total = 0
            while p:
                total += m.word(p)
                p = m.word(p + 2)
            return total
        available = free_bytes()
        m.input.extend(b'CLEAN\r'); allocations = 0; start = len(m.output)
        for _ in range(2000000):
            if m.cpu.pc in (m.labels['command_alloc'], m.labels['command_alloc_common']):
                allocations += 1
                if allocations == 10:
                    m.cpu.a = m.cpu.x = 255
            if not m.step():
                break
        else:
            self.fail('CLEAN did not finish')
        self.assertIn(b'?OUT OF MEMORY', m.output[start:])
        self.assertEqual(m.command('LIST'), before)
        self.assertEqual(free_bytes(), available)

    def test_clean_empty_and_malformed_source(self):
        m = self.m
        self.assertNotIn('?', m.command('CLEAN'))
        self.assertEqual(self.slab_counts(), [])
        self.assertEqual(m.word(0x28), 0)
        m.command('10 IF 0 THEN A=(');m.command('20 PRINT 7')
        before = m.command('LIST')
        self.assertNotIn('?', m.command('CLEAN'))
        self.assertEqual(m.command('LIST'), before)
        self.assertEqual(m.command('RUN').split('\r')[0], ' 7 ')

    def test_new_tokens_roundtrip_in_source_container(self):
        names = Names()
        source = 'IF RND(-1)>>3 THEN A=2<<4 ELSE A=8/2'
        tokens = tokenize(source, names)
        self.assertEqual(CODES['<<'], 0x1a);self.assertEqual(CODES['>>'], 0x1b)
        self.assertEqual(CODES['ELSE'], 0x68);self.assertEqual(CODES['CLEAN'], 0x69)
        data = dumps(names, {10: tokens, 20: tokenize('CLEAN', names)})
        loaded_names, lines = loads(data)
        self.assertEqual(tokenize(listing(lines[10], loaded_names), Names()), tokens)
