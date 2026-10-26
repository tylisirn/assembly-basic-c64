"""Raw memory file statements, including transport failures and program use."""
import unittest

from machine import Machine
from ab64.container import dumps, loads
from ab64.tokens import CODES, Names, listing, tokenize


class BinaryFileTests(unittest.TestCase):
    def setUp(self):
        self.m = Machine().boot()
        self.assertNotIn('?', self.m.command('RESERVE $C000,$400'))

    def assert_recovered(self):
        m = self.m
        self.assertIsNone(m.channel)
        self.assertFalse(m.input_channel or m.output_channel or m.status_talking)
        self.assertEqual(m.memory.bank, 0)
        self.assertEqual(m.command('PRINT 7').split('\r')[0], ' 7 ')

    def test_exact_raw_roundtrip_and_required_drive(self):
        m = self.m
        data = bytes(range(256)) + b'\x00\x80\xff'
        m.memory.ram[0xc000:0xc000+len(data)] = data
        start = len(m.services)
        self.assertNotIn('?', m.command(f'BSAVE "SPRITE.BIN",9,$C000,{len(data)}'))
        self.assertEqual(m.files['SPRITE.BIN'], data)
        self.assertIn((0xffba, 7, 1, 9, 2), m.services[start:])
        self.assertEqual(m.filename, 'SPRITE.BIN,S,W')
        self.assertNotIn('?', m.command('BLOAD "SPRITE.BIN",9,$C200'))
        self.assertEqual(bytes(m.memory.ram[0xc200:0xc200+len(data)]), data)
        self.assertEqual(m.filename, 'SPRITE.BIN,S,R')
        self.assert_recovered()

    def test_short_long_empty_zero_and_page_boundary_loads(self):
        m = self.m
        for data, count in ((b'\x80\0\xff', None), (b'\x80\0\xff', 20),
                            (bytes(range(100)), 3), (b'', None), (b'', 20),
                            (b'ABC', 0), (bytes(range(256))*2, None)):
            with self.subTest(length=len(data), count=count):
                m.files['DATA'] = data
                m.memory.ram[0xc0ff:0xc3ff] = b'\x55'*768
                suffix = '' if count is None else f',{count}'
                self.assertNotIn('?', m.command('BLOAD "DATA",8,$C0FF'+suffix))
                n = len(data) if count is None else min(count, len(data))
                self.assertEqual(bytes(m.memory.ram[0xc0ff:0xc3ff]),
                                 data[:n]+b'\x55'*(768-n))
        self.assertNotIn('?', m.command('BSAVE "EMPTY",8,$C000,0'))
        self.assertEqual(m.files['EMPTY'], b'')
        self.assert_recovered()

    def test_banked_ram_and_io_match_peek_poke(self):
        m = self.m
        self.assertNotIn('?', m.command('RESERVE $A000,$100'))
        m.files['SHADOW'] = b'\x00\x80\xff'
        self.assertNotIn('?', m.command('BLOAD "SHADOW",8,$A000'))
        self.assertEqual(bytes(m.memory.ram[0xa000:0xa003]), m.files['SHADOW'])
        self.assertNotIn('?', m.command('BSAVE "COPY",8,$A000,3'))
        self.assertEqual(m.files['COPY'], m.files['SHADOW'])
        m.files['COLOR'] = b'\x06'
        self.assertNotIn('?', m.command('BLOAD "COLOR",8,$D021,1'))
        self.assertEqual(m.memory.ram[0xd021], 6)
        self.assertNotIn('?', m.command('BSAVE "COLORCOPY",8,$D021,1'))
        self.assertEqual(m.files['COLORCOPY'], b'\x06')

    def test_program_execution_expressions_if_else_and_source_roundtrip(self):
        m = self.m
        m.files['RAW'] = b'\x01\x08\x00\xff'
        lines = [
            '10 F$="RAW":D%=8:A%=$C000:N%=4',
            '20 IF 0 THEN BLOAD "SKIP",D%,A% ELSE BLOAD F$,D%,A%+1',
            '30 BSAVE "COPY",D%,A%+1,N%:PRINT 9',
            '40 IF 1 THEN BSAVE "TRUE",8,$C001,4 ELSE PRINT 0',
        ]
        for line in lines:
            self.assertNotIn('?', m.command(line))
        expected = m.command('LIST')
        self.assertNotIn('?', m.command('SAVE "SOURCE"'))
        source = bytes(m.files['SOURCE'])
        self.assertEqual(dumps(*loads(source)), source)
        m.command('NEW')
        self.assertNotIn('?', m.command('LOAD "SOURCE"'))
        self.assertEqual(m.command('LIST'), expected)
        self.assertEqual(m.command('RUN').split('\r')[0], ' 9 ')
        self.assertEqual(m.files['COPY'], m.files['RAW'])
        self.assertEqual(m.files['TRUE'], m.files['RAW'])
        self.assertNotIn('SKIP', m.files)
        self.assert_recovered()

    def test_arguments_evaluated_once(self):
        m = self.m
        # USR increments $0720 and returns one, so each numeric argument can
        # have an observable side effect without damaging interpreter state.
        m.memory.ram[0x700:0x708] = bytes.fromhex('ee2007a901a20060')
        m.memory.ram[0x311:0x313] = b'\0\7'
        m.files['RAW'] = b'\x42\x43'
        self.assertNotIn('?', m.command('BLOAD "RAW",7+USR(0),$BFFF+USR(0),USR(0)'))
        self.assertEqual(m.memory.ram[0x720], 3)
        self.assertEqual(m.memory.ram[0xc000], 0x42)
        self.assertNotIn('?', m.command('BSAVE "COPY",7+USR(0),$BFFF+USR(0),USR(0)'))
        self.assertEqual(m.memory.ram[0x720], 6)
        self.assertEqual(m.files['COPY'], b'\x42')

    def test_invalid_arguments_never_open_or_modify_files(self):
        m = self.m
        for operation in ('BLOAD', 'BSAVE'):
            suffixes = [('', 'SYNTAX ERROR'), (',8', 'SYNTAX ERROR'),
                        (',8,', 'SYNTAX ERROR'), (',8,,1', 'SYNTAX ERROR'),
                        (',8,$C000,', 'SYNTAX ERROR'),
                        (',8,$C000,1,2', 'SYNTAX ERROR'),
                        (',8,$C000,1 X', 'SYNTAX ERROR'),
                        (',8,$C000,1)', 'SYNTAX ERROR'),
                        (',8,$C000,1+', 'SYNTAX ERROR'),
                        (',8,$C000,1 STRAY', 'SYNTAX ERROR'),
                        (',256,$C000,1', 'ILLEGAL QUANTITY'),
                        (',-1,$C000,1', 'ILLEGAL QUANTITY'),
                        (',"X",$C000,1', 'TYPE MISMATCH'),
                        (',8,"X",1', 'TYPE MISMATCH'),
                        (',8,$C000,"X"', 'TYPE MISMATCH'),
                        (',8,$C000,-1', 'ILLEGAL QUANTITY'),
                        (',8,$FFFF,2', 'ILLEGAL QUANTITY')]
            if operation == 'BSAVE':
                suffixes.append((',8,$C000', 'SYNTAX ERROR'))
            for suffix, error in suffixes:
                with self.subTest(operation=operation, suffix=suffix):
                    m.files['KEEP'] = bytearray(b'KEEP')
                    start = len(m.services)
                    self.assertIn('?'+error, m.command(operation+' "KEEP"'+suffix))
                    self.assertEqual(m.files['KEEP'], b'KEEP')
                    self.assertFalse(any(pc == 0xffc0 for pc, *_ in m.services[start:]))
            start = len(m.services)
            self.assertIn('?TYPE MISMATCH', m.command(operation+' 1,8,$C000,1'))
            self.assertIn('?SYNTAX ERROR', m.command(operation+' "",8,$C000,1'))
            self.assertFalse(any(pc == 0xffc0 for pc, *_ in m.services[start:]))
        self.assert_recovered()

    def test_top_of_memory_does_not_wrap(self):
        m = self.m
        # Writing the existing interrupt-vector bytes keeps firmware intact.
        tail = bytes(m.memory.ram[0xfffe:0x10000])
        for count in ('', ',2'):
            m.files['TAIL'] = tail
            self.assertNotIn('?', m.command('BLOAD "TAIL",8,$FFFE'+count))
        m.files['OVERFLOW'] = tail+b'X'
        zero_page = m.memory.ram[0]
        self.assertIn('?ILLEGAL QUANTITY', m.command('BLOAD "OVERFLOW",8,$FFFE'))
        self.assertEqual(m.memory.ram[0], zero_page)
        self.assertNotIn('?', m.command('BSAVE "TAILCOPY",8,$FFFE,2'))
        self.assertEqual(m.files['TAILCOPY'], tail)
        self.assert_recovered()

    def test_transport_errors_and_retry(self):
        m = self.m
        for operation in ('BLOAD', 'BSAVE'):
            select = 0xffc6 if operation == 'BLOAD' else 0xffc9
            byte = 0xffcf if operation == 'BLOAD' else 0xffd2
            for address, flag in ((0xffc0, 'carry'), (0xffc0, 'status'),
                                  (select, 'carry'), (select, 'status'),
                                  (byte, 'status'), (0xffc3, 'status')):
                with self.subTest(operation=operation, address=address, flag=flag):
                    m.files['RAW'] = b'ABC'
                    original_step = m.step
                    injected = False

                    def step():
                        nonlocal injected
                        pc = m.cpu.pc
                        transferring = m.input_channel or m.output_channel
                        result = original_step()
                        if (pc == address and not injected and
                                (address != byte or transferring)):
                            injected = True
                            if flag == 'carry':
                                m.cpu.p |= 1
                            else:
                                m.memory.ram[0x90] = 0x80
                        return result

                    m.step = step
                    try:
                        self.assertIn('?DEVICE ERROR', m.command(operation+' "RAW",8,$C000,3'))
                        self.assertTrue(injected)
                        self.assert_recovered()
                    finally:
                        m.step = original_step
                    self.assertNotIn('?', m.command(operation+' "RAW",8,$C000,3'))
        self.assertIn('?DEVICE ERROR', m.command('BLOAD "MISSING",8,$C000'))
        self.assert_recovered()

    def test_save_checks_final_dos_status(self):
        m = self.m
        for status in (b'63,FILE EXISTS,00,00\r', b'72,DISK FULL,00,00\r',
                       b'26,WRITE PROTECT ON,00,00\r', b'', b'00,OK'):
            with self.subTest(status=status):
                m.device_status = status
                self.assertIn('?DEVICE ERROR', m.command('BSAVE "RAW",8,$C000,1'))
                self.assert_recovered()
        m.device_status = b'00,OK,00,00\r'
        self.assertNotIn('?', m.command('BSAVE "RAW",8,$C000,1'))

    def test_host_tokens_keep_existing_assignments_and_keyword_boundaries(self):
        self.assertEqual(CODES['RESERVE'], 0x6a)
        self.assertEqual(CODES['BLOAD'], 0x6b)
        self.assertEqual(CODES['BSAVE'], 0x6c)
        names = Names()
        for source in ('BLOAD "RAW",8,$C000', 'BLOAD "RAW",8,$C000,64',
                       'BSAVE "RAW",8,$C000,64', 'BLOADER=1:BSAVER=2'):
            tokens = tokenize(source, names)
            self.assertEqual(tokenize(listing(tokens, names), names), tokens)
        self.assertEqual(names.names, ['BLOADER', 'BSAVER'])


if __name__ == '__main__':
    unittest.main()
