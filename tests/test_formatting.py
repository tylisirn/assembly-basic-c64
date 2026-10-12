"""Canonical call/group spacing and spaced TAB/SPC recognition on host and target."""
from pathlib import Path
import unittest
from machine import Machine
from ab64.tokens import Names, tokenize, listing
from ab64.cli import text_program
from ab64.container import dumps, loads

ROOT=Path(__file__).resolve().parents[1]

class FormattingTests(unittest.TestCase):
    CASES=(
        ('print tab ( 11 )"mission ended"','PRINT TAB(11) "mission ended"'),
        ('print chr$ ( 147 )','PRINT CHR$(147)'),
        ('x=(1+2)*3','X = (1 + 2) * 3'),
        ('print chr$ (205+(abs (rnd (1)) >> 14));',
         'PRINT CHR$(205 + (ABS(RND(1)) >> 14));'),
        ('print mid$ ( " a b " , 1 , len ( "abc" ) )',
         'PRINT MID$(" a b ", 1, LEN("abc"))'),
        ('dim a (2):a(1)=3:print a ( 1 )', 'DIM A(2) : A(1) = 3 : PRINT A(1)'),
        ('def fn f (x)=(x+2)*3:print fn f (1)',
         'DEF FN F(X) = (X + 2) * 3 : PRINT FN F(1)'),
        ('DATA -1,+2,001,-$d,"TAB ( 11 )",WORD:REM keep  ( raw )',
         'DATA -1, +2, 001, -$d, "TAB ( 11 )", WORD : REM keep  ( raw )'),
        ('PRINT "(",";"','PRINT "(", ";"'),
        ('PRINT FRE ( )','PRINT FRE()'),
    )

    def test_host_and_target_canonical_listing_and_roundtrip(self):
        m=Machine().boot()
        for source,expected in self.CASES:
            with self.subTest(source=source):
                names=Names();tokens=tokenize(source,names)
                self.assertEqual(listing(tokens,names),expected)
                self.assertEqual(tokenize(expected,names),tokens)
                m.command('NEW')
                self.assertNotIn('?',m.command('10 '+source))
                rows=m.command('LIST').split('\r')
                self.assertIn('10 '+expected,rows)
                m.command('SAVE "CANONICAL"')
                target_names,target_lines=loads(bytes(m.files['CANONICAL']))
                self.assertEqual(listing(target_lines[10],target_names),expected)
                self.assertEqual(target_lines[10],tokenize(expected,target_names))

    def test_spaced_tab_spc_execute_without_array_bindings(self):
        for call,expected in [('TAB ( 11 )',' '*11),('SPC ( 3 )',' '*3),
                              ('T'+chr(0xc1)+' (11)',' '*11),
                              ('S'+chr(0xd0)+' (3)',' '*3)]:
            m=Machine().boot()
            self.assertEqual(m.command('PRINT '+call+'"X"').split('\r')[0],expected+'X')
            self.assertEqual(m.word(0xb00+152),0,'Builtin calls must not create array records')
        self.assertEqual(Machine().boot().command('TAB=7:PRINT TAB').split('\r')[0],' 7 ')

    def test_host_punctuated_abbreviations_and_name_boundaries(self):
        for spelling,canonical in [('TA. (11)','TAB(11)'),('SP. (3)','SPC(3)'),
                                    ('T'+chr(0xc1)+' (11)','TAB(11)'),
                                    ('S'+chr(0xd0)+' (3)','SPC(3)')]:
            names=Names()
            self.assertEqual(tokenize('PRINT '+spelling,names),tokenize('PRINT '+canonical,names))
        names=Names()
        tokenize('TABLE=1:SPCOUNT=2:TAB=3:SPC=4',names)
        self.assertEqual(names.names,['TABLE','SPCOUNT','TAB','SPC'])

    def test_imported_spaced_calls_execute_and_list_compactly(self):
        m=Machine().boot()
        source='10 PRINT TAB ( 11 )"mission ended"\n20 PRINT CHR$ ( 65 );SPC ( 2 );"B"\n'
        m.files['CALLS']=dumps(*text_program(source))
        self.assertNotIn('?',m.command('LOAD "CALLS"'))
        self.assertEqual(m.command('RUN').split('\r')[:2],[' '*11+'mission ended','A  B'])
        listed=m.command('LIST')
        self.assertIn('10 PRINT TAB(11) "mission ended"\r',listed)
        self.assertIn('20 PRINT CHR$(65); SPC(2); "B"\r',listed)
        self.assertEqual(m.word(0xb00+152),0)
