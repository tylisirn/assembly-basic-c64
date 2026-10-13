"""File statement arguments are fully validated before opening the transport."""
import unittest
from machine import Machine
from ab64.container import loads

class FileArgumentTests(unittest.TestCase):
    def setUp(self):
        self.m=Machine().boot();self.m.command('10 A=7:PRINT A')

    def test_optional_secondary_roundtrip_and_sequential_channel(self):
        m=self.m
        self.assertNotIn('?',m.command('SAVE "BASE"'))
        expected=bytes(m.files['BASE'])
        for secondary in (0,1,255):
            with self.subTest(secondary=secondary):
                start=len(m.services)
                self.assertNotIn('?',m.command(f'SAVE "VOID2.AB",8,{secondary}'))
                self.assertEqual(bytes(m.files['VOID2.AB']),expected)
                self.assertEqual(sorted(loads(bytes(m.files['VOID2.AB']))[1]),[10])
                self.assertIn((0xffba,7,1,8,2),m.services[start:])
                self.assertNotIn('?',m.command(f'VERIFY "VOID2.AB",8,{secondary}'))
                m.command('NEW')
                self.assertNotIn('?',m.command(f'LOAD "VOID2.AB",8,{secondary}'))
                self.assertEqual(m.command('RUN').split('\r')[0],' 7 ')

    def test_arguments_are_evaluated_once_and_colon_else_boundaries_work(self):
        m=self.m
        m.memory.ram[0x700:0x708]=bytes.fromhex('ee2007a901a20060')
        m.memory.ram[0x311:0x313]=b'\0\7'
        self.assertNotIn('?',m.command('SAVE "SIDE",8,USR(0):PRINT 9'))
        self.assertEqual(m.memory.ram[0x720],1)
        self.assertNotIn('?',m.command('IF 1 THEN SAVE "TRUE",8,1 ELSE PRINT 0'))
        self.assertIn('TRUE',m.files)
        self.assertNotIn('?',m.command('IF 0 THEN SAVE "SKIP",8,1 ELSE PRINT 3'))
        self.assertNotIn('SKIP',m.files)
        self.assertNotIn('?',m.command('D%=8:S%=1:SAVE "EXPR",D%,S%'))
        self.assertEqual(m.files['EXPR'],m.files['TRUE'])

    def test_malformed_save_does_not_create_or_overwrite_file(self):
        m=self.m
        for suffix in (',8,1,99',',8,1 X',',8,',',8,,1',',8,1)',',8,1+',' X'):
            with self.subTest(suffix=suffix):
                m.files['BAD']=bytearray(b'KEEP')
                start=len(m.services)
                self.assertIn('?',m.command('SAVE "BAD"'+suffix))
                self.assertEqual(m.files['BAD'],b'KEEP')
                self.assertFalse(any(pc==0xffc0 for pc,*_ in m.services[start:]))
                self.assertIn('?',m.command('SAVE "ABSENT"'+suffix))
                self.assertNotIn('ABSENT',m.files)

        # Token $ff is a valid compact name ID, not an end-of-line marker.
        first_id=m.word(0x28)
        for i in range(128-first_id):
            m.command(f'N{i}=0')
        self.assertEqual(m.word(0x28),128)
        compact_name=f'N{127-first_id}'
        m.files['BAD']=bytearray(b'KEEP')
        start=len(m.services)
        self.assertIn('?SYNTAX ERROR',m.command('SAVE "BAD",8,1 '+compact_name))
        self.assertEqual(m.files['BAD'],b'KEEP')
        self.assertFalse(any(pc==0xffc0 for pc,*_ in m.services[start:]))

    def test_invalid_secondary_rejected_before_io(self):
        m=self.m
        for operation in ('SAVE','LOAD','VERIFY'):
            for argument,diagnostic in (('256','?ILLEGAL QUANTITY'),('-1','?ILLEGAL QUANTITY'),
                                        ('"X"','?TYPE MISMATCH')):
                with self.subTest(operation=operation,argument=argument):
                    m.files['BAD']=bytearray(b'KEEP')
                    before=m.command('LIST');start=len(m.services)
                    self.assertIn(diagnostic,m.command(f'{operation} "BAD",8,{argument}'))
                    self.assertEqual(m.files['BAD'],b'KEEP')
                    self.assertFalse(any(pc==0xffc0 for pc,*_ in m.services[start:]))
                    self.assertEqual(m.command('LIST'),before)

    def test_malformed_load_and_verify_do_not_publish_or_open(self):
        m=self.m;m.command('SAVE "GOOD",8')
        expected=m.command('LIST')
        for operation in ('LOAD','VERIFY'):
            for suffix in (',8,1,0',',8,1 X',',8,'):
                with self.subTest(operation=operation,suffix=suffix):
                    start=len(m.services)
                    self.assertIn('?SYNTAX ERROR',m.command(operation+' "GOOD"'+suffix))
                    self.assertEqual(m.command('LIST'),expected)
                    self.assertFalse(any(pc==0xffc0 for pc,*_ in m.services[start:]))
