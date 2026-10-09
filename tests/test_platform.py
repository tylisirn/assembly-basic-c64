import binascii
import random
import unittest
from machine import Machine
from ab64.container import dumps,loads
from ab64.tokens import Names,tokenize,word

class PlatformTests(unittest.TestCase):
    def setUp(self):self.m=Machine().boot()
    def test_shadow_execution_and_io(self):
        for address in (0x8000,0xa000,0xc000,0xe000):
            m=Machine().boot()
            m.command('10 X=0:GOTO 20')
            m.command('20 X=123:POKE $D021,1:PRINT X:END')
            head=m.state('head');first=m.word(head+5)
            second=m.word(first-2+m.word(first-2)-2)
            payload=m.word(second+5);size=m.word(payload-2)
            m.command('20')
            # Existing stable names and target allow the next payload to use shadow RAM.
            m.memory.ram[0xb00:0xb02]=word(address)
            m.memory.ram[address:address+4]=word(size)+b'\0\0'
            m.command('20 X=123:POKE $D021,1:PRINT X:END')
            self.assertEqual(m.word(second+5),address+2)
            self.assertEqual(m.command('RUN').split('\r')[0],' 123 ')
            self.assertEqual(m.memory.ram[0xd021],1)
            self.assertEqual(m.memory.ram[1]&7,7)
    def test_irq_and_nmi_frames(self):
        m=self.m;c=m.cpu
        for name in ('irq','nmi'):
            c.pc=0x700;c.sp=0xfd;c.a=0x11;c.x=0x22;c.y=0x33;c.p=0x21
            m.memory.ram[1]=0x35
            getattr(c,name)()
            for _ in range(200):
                m.step()
                if c.pc==0x700:break
            self.assertEqual((c.pc,c.sp,c.a,c.x,c.y,c.p&0xcf),(0x700,0xfd,0x11,0x22,0x33,0x01))
            self.assertEqual(m.memory.ram[1],0x35)
        # Test $0318 entry separately under the real stock pre-save dispatch shape.
        c.pc=0x700;c.sp=0xfd;c.a=0x44;c.x=0x55;c.y=0x66;c.p=0x21
        m.memory.ram[1]=0x37;c.nmi()
        for _ in range(100):
            m.step()
            if c.pc==0x700:break
        self.assertEqual((c.pc,c.sp,c.a,c.x,c.y),(0x700,0xfd,0x44,0x55,0x66))
        self.assertEqual(m.memory.ram[0x77],1)
    def test_sys_usr_map_recovery(self):
        m=self.m
        m.memory.ram[0x700:0x709]=bytes.fromhex('a9378501a934a21260')
        self.assertNotIn('?',m.command('SYS $0700:POKE $D021,1'))
        self.assertEqual(m.memory.ram[0xd021],1)
        m.memory.ram[0x311:0x313]=word(0x700)
        self.assertEqual(m.command('PRINT USR(1)').split('\r')[0],' 4660 ')
    def test_runtime_refresh(self):
        m=self.m;m.command('10 PRINT 2')
        m.memory.ram[m.labels['push_number']]=0
        self.assertEqual(m.command('RUN').split('\r')[0],' 2 ')
    def test_failed_edit_preserves_source(self):
        m=self.m;m.command('10 PRINT 1')
        old_head=m.state('head');old_payload=m.word(old_head+5)
        m.memory.ram[0xb00:0xb02]=b'\0\0'
        self.assertIn('?OUT OF MEMORY',m.command('10 PRINT 2'))
        self.assertEqual(m.word(old_head+5),old_payload)
        self.assertEqual(m.command('RUN').split('\r')[0],' 1 ')
    def test_files_roundtrip_crc_and_rollback(self):
        m=self.m
        for s in ('10 A=1:PRINT A','20 DATA 001,$D000,"A:B"'):m.command(s)
        m.command('SAVE "T.AB"')
        data=bytes(m.files['T.AB']);n,ll=loads(data)
        self.assertEqual(dumps(n,ll),data)
        self.assertNotIn('?',m.command('VERIFY "T.AB"'))
        m.command('NEW');m.command('LOAD "T.AB"')
        m.command('SAVE "U.AB"')
        self.assertEqual(m.files['U.AB'],m.files['T.AB'])
        old=m.command('LIST')
        m.files['BAD']=bytearray(data);m.files['BAD'][-1]^=1
        self.assertIn('?SYNTAX ERROR',m.command('LOAD "BAD"'))
        self.assertEqual(m.command('LIST'),old)
        m.files['EXTRA']=bytearray(data+b'x')
        self.assertIn('?SYNTAX ERROR',m.command('LOAD "EXTRA"'))
        self.assertEqual(m.command('LIST'),old)
    def test_long_imported_names(self):
        m=self.m;n=Names();name='A'*255
        data=dumps(n,{10:tokenize(name+'=3:PRINT '+name,n)})
        m.files['LONG']=bytearray(data)
        self.assertNotIn('?',m.command('LOAD "LONG"'))
        self.assertEqual(m.command('RUN').split('\r')[0],' 3 ')
        m.command('SAVE "COPY"')
        self.assertEqual(m.files['COPY'],data)
    def test_bad_binary_source_rollback(self):
        m=self.m;m.command('10 PRINT 7');original=m.command('LIST')
        for tokens in (b'\x1c',b'\x6b',b'\x10\x01',b'\x13\x02A',b'\x19\0\0',b'\x18\0',b'\x14\0'):
            data=b'AB64SRC\0\1\0\0\0'+word(10)+bytes((len(tokens),))+tokens+b'\xff\xff'
            data+=word(binascii.crc_hqx(data,65535));m.files['BAD']=bytearray(data)
            self.assertIn('?SYNTAX ERROR',m.command('LOAD "BAD"'),tokens.hex())
            self.assertEqual(m.command('LIST'),original)
    def test_arrays_functions_and_clear(self):
        m=self.m
        for s in ('10 DIM A(2,3),S$(2):A(1,2)=123:S$(1)="OK"','20 DEF FN DOUBLE(X)=X*2:PRINT FN DOUBLE(A(1,2));S$(1)'):m.command(s)
        for _ in range(2):
            self.assertEqual(m.command('RUN').split('\r')[0],' 246 OK')
        self.assertIn('?ILLEGAL QUANTITY',m.command('PRINT A(-1,0)'))
        self.assertIn('?ILLEGAL QUANTITY',m.command('DIM HUGE(32767,32767)'))
    def test_data_read_spelling(self):
        m=self.m
        m.command('10 DATA 001,53248,$D000,+1,-$000D')
        m.command('20 READ A$,B$,C$,D$,E$:PRINT A$;B$;C$;D$;E$')
        self.assertEqual(m.command('RUN').split('\r')[0],'00153248$D000+1-$000D')
        listing=m.command('LIST')
        self.assertIn('DATA 001,',listing)
    def test_gc_roots_and_code_stationarity(self):
        m=self.m
        m.command('10 A$="KEEP":DIM S$(2):S$(1)="ROOT":STOP:PRINT A$;S$(1)')
        m.command('RUN');head=m.state('head');payload=m.word(head+5)
        for _ in range(20):
            m.command('B$="ABC"+"DEF"')
            m.command('PRINT FRE(0)')
        self.assertEqual(m.word(head+5),payload)
        self.assertEqual(m.command('CONT').split('\r')[0],'KEEPROOT')
    def test_io_input_and_channels(self):
        m=self.m
        m.command('10 INPUT A,A$:PRINT A;A$')
        self.assertEqual(m.command('RUN\r123,HELLO').split('\r')[0],'?  123 HELLO')
        m.command('OPEN 2,8,2,"DEVICE,S,W"');m.command('PRINT# 2,"ABC"');m.command('CLOSE 2')
        self.assertEqual(m.files['DEVICE'],b'ABC\r')
    def test_nested_if_false_and_syntax_stub(self):
        m=self.m
        m.command('10 IF 0 THEN IF 1 THEN PRINT 9')
        m.command('20 IF 0 THEN A=(')
        m.command('30 PRINT 3')
        self.assertEqual(m.command('RUN').split('\r')[0],' 3 ')
        self.assertIn('20 IF',m.command('LIST'))
    def test_shifted_keyword_abbreviation(self):
        m=self.m;short='P'+chr(0xd2)
        self.assertEqual(m.command(short+' 3').split('\r')[0],' 3 ')
        m.command('10 '+short+' 7')
        self.assertIn('10 PRINT 7',m.command('LIST'))
        m.command('OPEN 2,8,2,"ABBREV,S,W"')
        self.assertNotIn('?',m.command(short+'# 2,"OK"'))
        self.assertEqual(m.files['ABBREV'],b'OK\r')
        n=Names()
        self.assertEqual(tokenize(short+' 3',n),tokenize('PRINT 3',n))
        self.assertEqual(tokenize(short+'# 2,"OK"',n),tokenize('PRINT# 2,"OK"',n))
    def test_read_array_targets(self):
        m=self.m
        m.command('10 DIM A(2),S$(1):DATA 001,$D000:READ S$(1),A(2):PRINT S$(1);A(2)')
        self.assertEqual(m.command('RUN').split('\r')[0],'001-12288 ')
    def test_clock_setter_and_wrapped_ti(self):
        m=self.m
        self.assertEqual(m.command('TI$="010203":PRINT TI$').split('\r')[0],'010203')
        self.assertEqual(m.jiffy,(3600+120+3)*60)
        m.jiffy=0xffff
        self.assertEqual(m.command('PRINT TI').split('\r')[0],'-1 ')
        self.assertIn('?ILLEGAL QUANTITY',m.command('TI$="240000"'))
    def test_bounded_recursive_function(self):
        self.assertIn('?FORMULA TOO COMPLEX',self.m.command('DEF FN F(X)=FN F(X):PRINT FN F(1)'))
        self.assertEqual(self.m.command('PRINT 7').split('\r')[0],' 7 ')
    def test_frozen_control_stack_boundary(self):
        m=self.m
        m.command('10 GOSUB 30:END');m.command('30 STOP:RETURN');m.command('RUN')
        self.assertIn('?RETURN WITHOUT GOSUB',m.command('RETURN'))
        self.assertIn("?CAN'T CONTINUE",m.command('CONT'))
    def test_open_defaults_and_excluded_devices(self):
        self.assertNotIn('?',self.m.command('OPEN 2,8'))
        self.assertIn('?UNSUPPORTED',self.m.command('OPEN 2'))
        self.assertIn('?UNSUPPORTED',self.m.command('OPEN 2,2'))
    def test_for_variable_reuse(self):
        m=self.m
        m.command('10 FOR I=1 TO 3:FOR I=1 TO 2:NEXT I:NEXT I')
        self.assertIn('?NEXT WITHOUT FOR',m.command('RUN'))
        m.command('10 FOR I=1 TO 1:GOSUB 30:NEXT I:PRINT I:END')
        m.command('30 FOR I=1 TO 1:NEXT I:RETURN')
        self.assertEqual(m.command('RUN').split('\r')[0],' 3 ')
    def test_numeric_get_rejects_nondigits(self):
        m=self.m
        self.assertEqual(m.command('GET A:PRINT A\r5').split('\r')[0],' 5 ')
        self.assertEqual(m.command('GET A:PRINT A').split('\r')[0],' 0 ')
        self.assertIn('?ILLEGAL QUANTITY',m.command('GET A\rX'))
    def test_cold_start_initializes_language_zero_page(self):
        m=Machine()
        m.memory.ram[2:0x79]=b'\xa5'*0x77
        m.boot()
        self.assertEqual(m.command('PRINT 7').split('\r')[0],' 7 ')
        self.assertEqual(m.memory.ram[0x65],0)
    def test_common_allocations_never_cross_the_cartridge_window(self):
        for address,size,expected in ((0x7ff0,32,0),(0x7fe0,32,0x7fe2),(0x7fe0,64,0x7fe2)):
            m=Machine().boot();c=m.cpu
            m.memory.ram[0xb00:0xb02]=word(address)
            m.memory.ram[address:address+4]=word(size)+b'\0\0'
            m.memory.ram[1]=0x35
            c.pc=m.labels['alloc_common'];c.a=32;c.x=0;c.sp=0xfd
            c.stPushWord(0x6ff)
            for _ in range(500):
                m.step()
                if c.pc==0x700:break
            self.assertEqual(c.pc,0x700)
            self.assertEqual(m.word(0x5b),expected)
    def test_payloads_preserve_common_arena_space(self):
        m=self.m;m.command('10 A=A+1')
        anchor=m.state('head')
        self.assertLess(anchor,0x8000)
        self.assertGreaterEqual(m.word(anchor+5),0x8000)

if __name__=='__main__':unittest.main()
