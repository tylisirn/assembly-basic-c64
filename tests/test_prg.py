"""Stock BASIC V2 token streams imported and compiled by the cartridge itself."""
import unittest
from machine import Machine
from ab64.container import loads
from ab64.tokens import listing, word


def stock_prg(rows):
    address = 0x801
    result = bytearray(word(address))
    for number, body in rows:
        address += 5 + len(body)
        result += word(address) + word(number) + body + b'\0'
    return result + b'\0\0'


class PrgImportTests(unittest.TestCase):
    def setUp(self):
        self.m = Machine().boot()

    def load(self, rows):
        self.m.files['STOCK'] = stock_prg(rows)
        return self.m.command('LOAD "STOCK",8')

    def test_compact_stock_tokens_compile_and_export_as_native_source(self):
        m = self.m
        m.command('100 PRINT 999')
        self.assertNotIn('?', self.load([
            (10, b'\x81I\xb21\xa43:\x99I;:\x82I'), (20, b'\x80')]))
        self.assertEqual(m.command('RUN').split('\r')[0], ' 1  2  3 ')
        text = m.command('LIST')
        self.assertIn('10 FOR I = 1 TO 3 : PRINT I; : NEXT I', text)
        self.assertNotIn('100 ', text)
        self.assertEqual(m.filename, 'STOCK')  # DOS file type is auto-detected
        m.command('SAVE "NATIVE"')
        names, lines = loads(bytes(m.files['NATIVE']))
        self.assertEqual(sorted(lines), [10, 20])
        self.assertIn('FOR I', listing(lines[10], names))
        m.command('NEW')
        self.assertNotIn('?', m.command('LOAD "NATIVE"'))
        self.assertIn(' 1  2  3 ', m.command('RUN'))

    def test_stock_name_significance_and_signed_integer_namespace(self):
        m = self.m
        self.assertNotIn('?', self.load([
            (10, b'LONGNAME\xb242:A B\xb25:A%\xb2\xab1:A\xb27'),
            (20, b'\x99LOONEY;AB;A%;A;A%\xb3A')]))
        self.assertEqual(m.command('RUN').split('\r')[0], ' 42  5 -1  7 -1 ')
        text = m.command('LIST')
        self.assertIn('PRGINTA', text)
        self.assertNotIn('LONGNAME', text)

    def test_quotes_rem_data_controls_and_go_to_are_preserved(self):
        m = self.m
        raw = b'A\x93\x99B'
        self.assertNotIn('?', self.load([
            (0, b'\x83"'+raw+b'",001,-2:\x8f'),
            (10, b'\x87A$,B,C:\x99A$;B;C:\xcb \xa430'),
            (20, b'\x99"WRONG"'),
            (30, b'\x8f \x99 \xff raw bytes'),
            (63999, b'\x80')]))
        output = m.command('RUN')
        self.assertIn(raw.decode('latin-1')+' 1 -2 ', output)
        self.assertNotIn('WRONG', output)
        m.command('SAVE "COPY"')
        names, lines = loads(bytes(m.files['COPY']))
        self.assertIn(raw, lines[0])
        self.assertIn(b' \x99 \xff raw bytes', lines[30])
        self.assertIn('GOTO 30', listing(lines[10], names))

    def test_relational_pairs_functions_arrays_and_control_flow(self):
        m = self.m
        self.assertNotIn('?', self.load([
            (10, b'\x86A(2):A(1)\xb2\xab8:\x96\xa5F(X)\xb2X\xac2'),
            (20, b'\x8bA(1)\xb3\xb20\xa7\x8d100'),
            (30, b'\x99\xa5F(3);\xb6(A(1));1\xb3\xb21;2\xb1\xb21;1\xb3\xb12:\x80'),
            (100, b'\x99"SUB";:\x8e')]))
        self.assertEqual(m.command('RUN').split('\r')[0], 'SUB 6  8 -1 -1 -1 ')

    def test_stock_get_hash_becomes_the_native_device_keyword(self):
        self.assertNotIn('?', self.load([(10, b'\xa1#1,A$:\x80')]))
        self.assertIn('GET# 1, A$', self.m.command('LIST'))

    def test_empty_program_and_unsupported_numeric_source_remain_editable(self):
        m = self.m
        m.command('10 PRINT 7')
        self.assertNotIn('?', self.load([]))
        self.assertNotIn('10 ', m.command('LIST'))
        self.assertNotIn('?', self.load([(10, b'\x99 1.5'), (20, b'\x99\xff')]))
        self.assertIn('1.5', m.command('LIST'))
        self.assertIn('?ILLEGAL QUANTITY', m.command('RUN'))

    def test_truncation_links_order_tokens_and_trailing_payload_roll_back(self):
        m = self.m
        m.command('10 A$="KEEP":DIM S$(1):S$(1)="ROOT":PRINT A$;S$(1)')
        m.command('RUN')
        before = m.command('LIST')
        data = stock_prg([(10, b'\x99"NEW"'), (20, b'\x80')])
        bad = [data[:i] for i in range(1, len(data))]
        bad += [data+b'\x60', b'\x00\x20'+data[2:],
                stock_prg([(64000, b'\x80')]),
                stock_prg([(20, b'\x80'), (10, b'\x80')]),
                stock_prg([(10, b'\x80'), (10, b'\x80')]),
                stock_prg([(10, b'\xcc')]), stock_prg([(10, b'\xcb1')]),
                stock_prg([(10, b'\x8f'+b'X'*254)])]
        for link in (0x801, 0x802, 0xffff):
            bad.append(data[:2]+word(link)+data[4:])
        for index, invalid in enumerate(bad):
            with self.subTest(index=index):
                m.files['BAD'] = invalid
                self.assertIn('?SYNTAX ERROR', m.command('LOAD "BAD",8'))
                self.assertEqual(m.command('LIST'), before)
                self.assertIn('KEEPROOT', m.command('PRINT A$;S$(1)'))
                self.assertEqual(m.memory.ram[0x65], 0)
                self.assertEqual(m.memory.bank, 0)

    def test_prg_can_end_exactly_at_the_stock_basic_memory_limit(self):
        m = self.m
        space = 0xa000 - 0x801 - 2
        body = b'A'+b' '*200+b'\xb21'
        count, remainder = divmod(space, 5+len(body))
        rows = [(10*(i+1), body) for i in range(count)]
        rows.append((10*(count+1), b'A'+b' '*(remainder-8)+b'\xb21'))
        data = stock_prg(rows)
        self.assertEqual(len(data), 0xa000-0x801+2)
        m.files['STOCK'] = data
        start = len(m.output)
        m.input.extend(b'LOAD "STOCK",8\r')
        m.pump(limit=10000000)
        self.assertNotIn(b'?', m.output[start:])
        self.assertIn(str(rows[-1][0])+' A = 1', m.command('LIST'))
        self.assertNotIn('?', m.command('RUN'))
        self.assertIn(' 1 ', m.command('PRINT A'))

    def test_allocation_failure_preserves_old_program(self):
        m = self.m
        m.command('10 PRINT 7')
        m.memory.ram[0xb00:0xb02] = b'\0\0'
        self.assertIn('?OUT OF MEMORY', self.load([(10, b'\x99"NEW"')]))
        self.assertIn('10 PRINT 7', m.command('LIST'))
        self.assertIn(' 7 ', m.command('RUN'))

    def test_empty_import_clears_editor_listing_for_both_source_formats(self):
        from ab64.container import dumps
        from ab64.tokens import Names
        for data in (stock_prg([]), dumps(Names(), {})):
            with self.subTest(header=data[:8]):
                m = self.m
                m.command('10 PRINT 7')
                m.files['EMPTY'] = data
                m.command('BASIC')
                m.input.extend(b'_LOAD "EMPTY",8\r');m.pump()
                self.assertEqual(bytes(m.memory.ram[0x400:0x720]), b' '*800)
                self.assertEqual(m.memory.ram[0x3cc+50], 255)
                m.input.extend(b'\x8610\r20 PRINT 2\r');m.pump()
                self.assertEqual(m.word(0x3cf), 20)
                self.assertEqual(bytes(m.memory.ram[0x400:0x402]), b'\xb2\xb0')
                m.input.extend(b'\x88');m.pump()

    def test_import_from_editor_keeps_hooks_and_updates_listing(self):
        m = self.m
        m.command('10 PRINT 7')
        m.files['STOCK'] = stock_prg([(100, b'\x99"NEW"'), (200, b'\x80')])
        m.command('BASIC')
        m.input.extend(b'_LOAD "STOCK",8\r')
        m.pump()
        self.assertEqual(m.memory.ram[0x3cc], 1)
        self.assertEqual(m.word(0x326), m.labels['editor_output_gate'])
        self.assertEqual(m.word(0x3cf), 100)
        self.assertEqual(bytes(m.memory.ram[0x400:0x403]), b'\xb1\xb0\xb0')
        m.input.extend(b'RUN\r');m.pump()
        self.assertIn(b'NEW', m.output)
        self.assertEqual(m.memory.ram[0x3cc], 0)
