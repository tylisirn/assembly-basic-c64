"""Consumer-format checks for the cartridge artifacts, independent of the emitter."""
from pathlib import Path
import struct
import unittest

ROOT=Path(__file__).resolve().parents[1]


class CartridgeTests(unittest.TestCase):
    def test_vice_generic_16kb_layout(self):
        # VICE 3.7.1's generic_crt_attach handles two packets as Ultimax;
        # normal 16-KiB cartridges must reach its single-packet path.
        for directory in ('build','dist'):
            with self.subTest(directory=directory):
                data=(ROOT/directory/'assembly-basic.crt').read_bytes()
                rom=(ROOT/directory/'assembly-basic.bin').read_bytes()
                self.assertEqual(data[:16],b'C64 CARTRIDGE   ')
                header_size,version,kind,exrom,game=struct.unpack_from('>IHHBB',data,16)
                self.assertEqual((header_size,version,kind,exrom,game),(64,0x100,0,0,0))
                self.assertEqual(data[header_size:header_size+4],b'CHIP')
                packet_size,chip_kind,bank,start,size=struct.unpack_from('>IHHHH',data,header_size+4)
                self.assertEqual((chip_kind,bank,start,size),(0,0,0x8000,16384))
                self.assertEqual(packet_size,16+size)
                self.assertEqual(len(data),header_size+packet_size)
                self.assertEqual(data[header_size+16:],rom)
