"""Consumer-format checks, independent of the cartridge emitter."""
from pathlib import Path
import struct
import unittest
ROOT=Path(__file__).resolve().parents[1]

class CartridgeTests(unittest.TestCase):
    def test_magic_desk_64kb_layout(self):
        for directory in ('build','dist'):
            with self.subTest(directory=directory):
                data=(ROOT/directory/'assembly-basic.crt').read_bytes()
                rom=(ROOT/directory/'assembly-basic.bin').read_bytes()
                self.assertEqual(len(rom),65536)
                self.assertEqual(data[:16],b'C64 CARTRIDGE   ')
                self.assertEqual(struct.unpack_from('>IHHBB',data,16),(64,0x100,19,0,1))
                offset=64
                images=[]
                for number in range(8):
                    self.assertEqual(data[offset:offset+4],b'CHIP')
                    self.assertEqual(struct.unpack_from('>IHHHH',data,offset+4),
                                     (8208,0,number,0x8000,8192))
                    bank=data[offset+16:offset+8208]
                    self.assertEqual(bank[4:9],b'\xc3\xc2\xcd80')
                    images.append(bank)
                    offset+=8208
                self.assertEqual(offset,len(data))
                self.assertEqual(b''.join(images),rom)
