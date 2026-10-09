import binascii
import random
import unittest
from ab64.tokens import *
from ab64.container import dumps,loads

class TokenTests(unittest.TestCase):
    def test_worked_examples(self):
        n=Names()
        self.assertEqual(tokenize('V=$D000:POKE V+33,1',n),bytes.fromhex('80 0a 12 00 d0 00 37 80 05 10 21 01 71'))
        self.assertEqual(tokenize('V=53248:POKE V+33,1',n),bytes.fromhex('80 0a 11 00 d0 00 37 80 05 10 21 01 71'))
        self.assertEqual(tokenize('DATA 001,53248,$D000,"A:B"',n),bytes.fromhex('23 71 16 03 30 30 31 01 11 00 d0 01 12 00 d0 01 13 03 41 3a 42'))
    def test_every_word(self):
        n=Names()
        for v in range(65536):
            for radix in (10,16):
                s=immediate(v,radix)
                self.assertEqual(decode(s,n)[0].value,v)
                self.assertEqual(tokenize(listing(s,n),n),s)
    def test_name_boundaries(self):
        n=Names()
        for name in ('TOTAL','COSMIC','SCORE','SCORETOTAL','A','A%','A$','PRINTA','GOTO30'):
            tokenize(name,n)
        self.assertEqual(len(n.names),9)
        self.assertEqual(tokenize('score',n),tokenize('SCORE',n))
        for i in range(65535-len(n.names)):
            n.add(f'N{i}')
        for i in (0,127,128,65534):
            self.assertEqual(decode(name_token(i),n)[0].value,i)
        with self.assertRaises(SourceError):n.add('TOOMANY')
    def test_canonical_list(self):
        n=Names()
        s=tokenize('?scoretotal%+0001:goto 30',n)
        self.assertEqual(listing(s,n),'PRINT SCORETOTAL% + 1 : GOTO 30')
        for source in ['A$="PRINT : DATA":REM keep  these bytes','DATA 001,+0002,-$d,"X:Y",,WORD','A$="unterminated','PRINT .5,1.2,1E3,65536,$FFFFF','$d000+1','REM \0\x4c\x80\xff']:
            s=tokenize(source,n)
            self.assertEqual(tokenize(listing(s,n),n),s,source)
    def test_reject_malformed(self):
        n=Names(['A'])
        for s in (b'\x1c',b'\x6a',b'\x10\x00',b'\x11\xff\x00',b'\x19\0\0',b'\x13\x03x',b'\x18\0',b'\x14\0',b'\x2f',b'\x81',b'\x23\x15\x01\x31',b'\x23\x71\x16\x01\x32'):
            with self.assertRaises(SourceError,msg=s.hex()):decode(s,n)
    def test_transactional_tokenization(self):
        n=Names(['ORIGINAL'])
        with self.assertRaises(SourceError):tokenize('NEWNAME='+ '"'+ 'x'*255+'"',n)
        self.assertEqual(n.names,['ORIGINAL'])

class ContainerTests(unittest.TestCase):
    def test_crc_known_vector(self):
        self.assertEqual(binascii.crc_hqx(b'123456789',65535),0x29b1)
    def test_roundtrip_dense_names(self):
        n=Names(['UNUSED']+[f'N{i}' for i in range(150)])
        lines={0:tokenize('N149=$D000',n),63999:tokenize('REM \0\x80\xff',n)}
        data=dumps(n,lines)
        nn,ll=loads(data)
        self.assertEqual(nn.names,['N149'])
        self.assertEqual(ll[0][0],128)
        self.assertEqual(dumps(nn,ll),data)
    def test_empty(self):
        self.assertEqual(loads(dumps(Names(),{}))[1],{})
    def test_corruption_and_truncation(self):
        n=Names(); data=dumps(n,{10:tokenize('A=1',n)})
        for i in range(len(data)):
            with self.assertRaises(SourceError):loads(data[:i])
            corrupted=bytearray(data);corrupted[i]^=1
            with self.assertRaises(SourceError):loads(corrupted)
        with self.assertRaises(SourceError):loads(data+b'x')
    def test_fuzz_safe_decoder(self):
        r=random.Random(640)
        for _ in range(2000):
            b=r.randbytes(r.randint(1,255))
            try:decode(b,Names(['A']))
            except SourceError:pass

if __name__=='__main__':unittest.main()
