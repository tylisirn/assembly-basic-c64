"""Unsigned declarations, signed mixing and safe typed FRE runtime results."""
import random
import unittest
from machine import Machine
from ab64.tokens import Names, tokenize
from ab64.container import dumps

class UnsignedTests(unittest.TestCase):
    def setUp(self):self.m=Machine().boot()
    def result(self,command):return self.m.command(command).split('\r')[0]

    def test_bit_preserving_assignments_and_full_names(self):
        for bits in (0,1,32767,32768,53248,65535):
            signed=(bits+32768)%65536-32768
            self.assertEqual(self.result(f'A%={bits}:A=A%:B%=A:PRINT A%;A;B%'),
                             f' {bits} {signed: d}  {bits} ')
        self.assertEqual(self.result('SCORE%=65535:SCORETOTAL%=32768:PRINT SCORE%;SCORETOTAL%'),
                         ' 65535  32768 ')
        self.assertIn('?TYPE MISMATCH',self.m.command('A%="BAD"'))
        self.assertIn('?TYPE MISMATCH',self.m.command('A%=65535:PRINT A%+"BAD"'))
        self.assertIn('?TYPE MISMATCH',self.m.command('PRINT STR$("BAD")'))

    def test_unsigned_arithmetic_and_signed_mixing(self):
        m=self.m;m.command('U%=65535:V%=2')
        expected={'U%+V%':' 1 ','U%-V%':' 65533 ','U%*V%':' 65534 ',
                  'U%/V%':' 32767 ','U%+2':' 1 ','U%-2':' 65533 ','U%/2':' 32767 ',
                  'U%>V%':'-1 ','U%>2':'-1 ','U%=65535':'-1 ',
                  'U% AND V%':' 2 ','NOT U%':' 0 ','-V%':' 65534 ',
                  'ABS(U%)':' 65535 ','INT(U%)':' 65535 ','SGN(U%)':' 1 ',
                  'STR$(U%)':' 65535','STR$(U%+0)':' 65535',
                  'U%>>1':' 65535 ','U%<<1':' 65534 '}
        for expression,result in expected.items():
            self.assertEqual(self.result('PRINT '+expression),result,expression)
        m.command('U%=0:V%=1')
        self.assertEqual(self.result('PRINT U%-V%'),' 65535 ')
        m.command('U%=2:V%=16')
        self.assertEqual(self.result('PRINT U%^V%'),' 0 ')
        self.assertIn('?DIVISION BY ZERO',m.command('V%=0:PRINT U%/V%'))

    def test_random_unsigned_division_and_comparisons(self):
        rng=random.Random(65535)
        for left,right in [(65535,32768),(65535,65535),(32768,65535),(65535,1)]+[
                (rng.randrange(65536),rng.randrange(1,65536)) for _ in range(80)]:
            self.m.command(f'U%={left}:V%={right}')
            self.assertEqual(self.result('PRINT U%/V%'),f' {left//right} ')
            self.assertEqual(self.result('PRINT U%<V%'),'-1 ' if left<right else ' 0 ')
            self.assertEqual(self.result('PRINT U%>V%'),'-1 ' if left>right else ' 0 ')

    def test_arrays_data_input_functions_and_clean(self):
        m=self.m
        for line in ('10 DIM A%(2),S$(1):DATA 65535,32768:READ A%(0),A%(1)',
                     '20 DEF FN F%(X%)=X%:S$(0)=STR$(A%(0)):PRINT A%(0);A%(1);FN F%(A%(0));S$(0)'):
            m.command(line)
        expected=' 65535  32768  65535  65535'
        self.assertEqual(self.result('RUN'),expected)
        self.assertNotIn('?',m.command('CLEAN'))
        self.assertEqual(self.result('RUN'),expected)
        self.assertEqual(self.result('INPUT I%:PRINT I%\r65535'),'?  65535 ')
        self.assertEqual(self.result('DEF FN G(X%)=X%:PRINT FN G(65535)'),'-1 ')

    def test_unsigned_for_boundaries(self):
        for start,end,step,expected in [(32766,32769,1,' 32766  32767  32768  32769 '),
                                       (65534,65535,1,' 65534  65535 '),
                                       (1,0,-1,' 1  0 '),
                                       (32769,32766,-1,' 32769  32768  32767  32766 ')]:
            self.m.command('NEW')
            self.m.command(f'10 FOR I%={start} TO {end} STEP {step}:PRINT I%;:NEXT I%')
            self.assertEqual(self.result('RUN'),expected)

    def test_empty_fre_unsigned_and_continuation_preservation(self):
        m=self.m;m.command('10 A%=65535:DIM X%(1),S$(0):X%(1)=32768:S$(0)="KEEP":STOP:PRINT A%;X%(1);S$(0)')
        m.command('RUN');continuation=m.state('cont');head=m.state('head');payload=m.word(head+5)
        free=int(self.result('PRINT FRE()'))
        self.assertGreater(free,32767)
        self.assertLessEqual(free,43008)
        self.assertEqual(m.state('cont'),continuation)
        self.assertEqual(m.word(head+5),payload)
        self.assertEqual(self.result('CONT'),' 65535  32768 KEEP')
        self.assertEqual(self.result('PRINT FRE(0)=FRE()'),'-1 ')
        self.assertNotIn('?',m.command('10 F%=FRE():PRINT F%;:PRINT FRE()'))
        self.assertNotIn('?',m.command('RUN'))

    def test_unsigned_stack_and_array_values_are_not_string_roots(self):
        m=self.m;m.command('A$="DEAD":DIM X%(0)')
        pointer=m.state('name_head')
        while bytes(m.memory.ram[pointer+9:pointer+9+m.memory.ram[pointer+8]])!=b'A$':
            pointer=m.word(pointer)
        dead=m.word(pointer+5)
        m.command(f'U%={dead}:X%(0)={dead}:A$=""')
        m.command('PRINT U%+FRE()') # An unsigned numeric stack slot aliases the dead payload.
        free=m.state('free');covered=False
        while free:
            covered |= free<=dead-2<free+m.word(free)
            free=m.word(free+2)
        self.assertTrue(covered,'Unsigned numeric words must not retain unreachable strings')
        self.assertEqual(int(self.result('PRINT U%')),dead)

    def test_source_import_and_255_byte_unsigned_name(self):
        name='A'*254+'%';names=Names()
        data=dumps(names,{10:tokenize(name+'=65535:PRINT '+name,names)})
        self.m.files['UNSIGNED']=bytearray(data)
        self.assertNotIn('?',self.m.command('LOAD "UNSIGNED"'))
        self.assertEqual(self.result('RUN'),' 65535 ')
