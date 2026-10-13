import random
import unittest
from machine import Machine
from ab64.tokens import Names,decode,listing

class NativeTests(unittest.TestCase):
    def setUp(self):self.m=Machine().boot()
    def expression(self,s):
        out=self.m.command('PRINT '+s)
        return out.split('\r')[0]
    def test_boot_and_budgets(self):
        m=self.m
        self.assertIn(b'ASSEMBLY BASIC',m.output)
        for section,budget in [('GATEWAY',768),('RUNTIME',7162)]:
            self.assertLessEqual(m.labels[f'__{section}_SIZE__'],budget)
        self.assertEqual(m.memory.ram[1]&7,7)
    def test_word_semantics(self):
        cases={'32767+1':32768,'65535+1':0,'$FFFF*2':65534,'-5/2':-2,'65535/2':32767,'-32768/-1':-32768,'ABS(-32768)':-32768,'2^3^2':64,'-2^2':-4,'0^0':1,'NOT 1=1':0,'$D000<0':0,'SGN($FFFF)':1,'INT(2)':2}
        for source,expected in cases.items():
            self.assertEqual(self.expression(source),f'{expected: d} ',source)
    def test_required_poke_examples(self):
        for s in ('V=53248:POKE V+33,1','V=$D000:POKE V+$21,$01'):
            self.m.command('10 '+s)
            self.m.command('RUN')
            self.assertEqual(self.m.memory.ram[0xd021],1)
        self.assertIn('?ILLEGAL QUANTITY',self.m.command('POKE $D021,$FFFF'))
    def test_if_and_forward_anchor(self):
        m=self.m
        m.command('10 IF 0 THEN PRINT 1:PRINT 2')
        m.command('20 IF 1 THEN GOTO 40')
        m.command('30 PRINT 3')
        m.command('40 PRINT 4')
        self.assertEqual(m.command('RUN').split('\r')[0],' 4 ')
    def test_gosub_for_cont(self):
        m=self.m
        for s in ('10 FOR I=1 TO 3:GOSUB 30:NEXT I:STOP:PRINT 9:END','30 PRINT I;:RETURN'):m.command(s)
        self.assertEqual(m.command('RUN').split('\r')[0],' 1  2  3 ')
        self.assertEqual(m.command('CONT').split('\r')[0],' 9 ')
        m.command('20 PRINT 2')
        self.assertIn("?CAN'T CONTINUE",m.command('CONT'))
    def test_strings(self):
        m=self.m
        self.assertEqual(self.expression('"A"+"B"'),'AB')
        self.assertEqual(self.expression('LEN("A:B")'),' 3 ')
        self.assertEqual(self.expression('ASC("Z")'),' 90 ')
        self.assertEqual(self.expression('CHR$(65)'),'A')
        self.assertEqual(self.expression('STR$($D000)'),' 53248')
        self.assertEqual(self.expression('VAL("-$FFFF")'),' 1 ')
        self.assertEqual(self.expression('VAL("$1E2")'),' 482 ')
        self.assertIn('?ILLEGAL QUANTITY',m.command('PRINT VAL("65536")'))
    def test_replace_delete_layout(self):
        m=self.m
        for s in ('10 GOTO 30','20 PRINT 2','30 PRINT 3:END'):m.command(s)
        anchors=self.validate_graph()
        m.command('30 PRINT 7:END')
        self.assertEqual(self.validate_graph()[30],anchors[30])
        self.assertEqual(m.command('RUN').split('\r')[0],' 7 ')
        m.command('20')
        self.assertEqual(set(self.validate_graph()),{10,30})
        m.command('30')
        self.assertIn("?UNDEF'D STATEMENT",m.command('RUN'))
    def validate_graph(self):
        m=self.m; p=m.state('head'); result={};seen=set()
        while p!=m.labels['run_end']:
            self.assertNotIn(p,seen);seen.add(p)
            self.assertTrue(0x1400<=p<0x8000)
            self.assertEqual(m.memory.ram[p],0x4c)
            n=m.word(p+3); payload=m.word(p+5);size=m.word(payload-2)
            self.assertGreaterEqual(size,4)
            self.assertEqual(m.word(p+1),payload+1+m.memory.ram[payload])
            trailer=payload-2+size-3
            self.assertEqual(m.memory.ram[trailer],0x4c)
            self.assertGreater(n,max(result,default=-1))
            result[n]=p;p=m.word(trailer+1)
        return result
    def test_random_edits(self):
        r=random.Random(64);expected=set()
        for _ in range(100):
            n=r.randrange(60)
            if r.randrange(3):
                self.m.command(f'{n} PRINT {n}')
                expected.add(n)
            else:
                self.m.command(str(n));expected.discard(n)
            self.assertEqual(set(self.validate_graph()),expected)

if __name__=='__main__':unittest.main()
