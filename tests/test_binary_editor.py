"""Native keyboard workflows and source persistence for the binary/sprite mode."""
import unittest
from machine import Machine
from ab64.container import Blob, Reservation, ProgramLines, dumps, loads
from ab64.cli import text_program


class BinaryEditorTests(unittest.TestCase):
    def setUp(self):
        self.m = Machine().boot()

    def keys(self, value):
        self.m.input.extend(value.encode('latin-1'))
        self.m.pump(12000000)

    def metadata(self):
        return bytes(self.m.memory.ram[0x200:0x259]+self.m.memory.ram[0x2a7:0x2f7])

    def sprite(self):
        self.m.command('RESERVE $3C00,$200')
        self.m.command('SPRDEF')
        self.keys('\rNS\r')
        self.assertEqual(self.m.memory.ram[0xe40], 3)

    def binary(self, size=300):
        self.m.command('SPRDEF')
        self.keys('N$3C00\r$200\r\rNB'+str(size)+'\r\r')
        self.assertEqual(self.m.memory.ram[0xe40], 2)

    def record_video_writes(self):
        from machine import Memory

        class RecordingMemory(Memory):
            def __setitem__(self, address, value):
                if 0x400 <= address < 0x7e8 or 0xd800 <= address < 0xdbe8:
                    self.video_writes.append((address, value))
                super().__setitem__(address, value)

        self.m.memory.__class__ = RecordingMemory
        self.m.memory.video_writes = []
        return self.m.memory.video_writes

    def test_blob_focus_retains_reservation_and_updates_only_changed_rows(self):
        self.sprite()
        self.keys('_NS_')  # two sprites, reservation focus
        m = self.m
        reservation = bytes(m.memory.ram[0x428:0x450])
        self.assertTrue(all(c & 128 for c in reservation))
        writes = self.record_video_writes()
        self.keys('\r')
        self.assertEqual(bytes(m.memory.ram[0x428:0x450]), reservation)
        self.assertFalse(any(0x428 <= p < 0x450 for p, _ in writes))
        writes.clear()
        self.keys('\x11')
        self.assertTrue(writes)
        self.assertTrue(all(0x400 <= p < 0x7e8 and (p-0x400)//40 in (2,3,20)
                            for p, _ in writes))
        self.assertEqual(len(writes), len({p for p, _ in writes}))
        self.assertEqual(bytes(m.memory.ram[0x428:0x450]), reservation)

    def test_sprite_paint_and_palette_do_not_redraw_other_cells(self):
        self.sprite()
        self.keys('I1')
        m = self.m
        writes = self.record_video_writes()
        self.keys('2')
        self.assertEqual(writes, [(0xd800+2*40+2, 7)])
        self.assertEqual(m.memory.ram[0xc00], m.memory.ram[0x3c00])
        writes.clear()
        self.keys('2\x1d')
        self.assertEqual(writes, [])
        self.keys('TC2')
        writes.clear()
        self.keys('\x1d')
        self.assertEqual(len(writes), 2)  # old/new palette selection digits
        self.assertTrue(all(0x400+23*40 <= p < 0x400+24*40 for p, _ in writes))

    def test_sprite_preview_frame_negative_rulers_and_centered_hardware(self):
        self.sprite()
        self.keys('C12\r')
        m = self.m
        for row in range(1,10):
            for col in range(28,40):
                self.assertEqual(m.memory.ram[0x400+row*40+col], 0xa0)
                self.assertEqual(m.memory.ram[0xd800+row*40+col], 2)
        for row in range(25):
            self.assertEqual(m.memory.ram[0x400+row*40+26], 0xa0)
            self.assertEqual(m.memory.ram[0xd800+row*40+26], 14)
        for row,col in [(0,11),(0,21),(1,2),(23,2),(2,0)]:
            self.assertEqual(m.memory.ram[0x400+row*40+col], ord('1' if col!=21 else '2')|128)
            self.assertEqual(m.memory.ram[0xd800+row*40+col], 14)
        for col in range(27):
            self.assertEqual(m.memory.ram[0x400+24*40+col], 0xa0)
        self.assertEqual(m.memory.ram[0xd004]+12, 24+(29+1)*8)
        self.assertEqual(m.memory.ram[0xd006]+256+24, 24+(35+1)*8)
        self.keys('T')
        self.assertEqual(m.memory.ram[0x400+40+3], ord('.')|128)

    def test_hex_navigation_and_noop_entry_only_write_changed_cells(self):
        self.binary()
        self.keys('00')
        writes = self.record_video_writes()
        self.keys('0')
        self.assertEqual(writes, [])
        before = self.m.steps
        self.keys('\x1d')
        self.assertLess(self.m.steps-before, 10000)  # no full viewport formatting
        self.assertTrue(writes)
        self.assertTrue(all(0x400 <= p < 0x7e8 and (p-0x400)//40 in (2,23)
                            for p, _ in writes))
        self.assertEqual(len(writes), len({p for p, _ in writes}))
        # A shorter decimal word must erase the previous footer's suffix.
        self.m.memory.ram[0x3c01:0x3c04] = b'\xff\xff\0'
        self.keys('FF')
        self.assertIn(b'65535', bytes(self.m.memory.ram[0x798:0x7c0]))
        self.m.memory.ram[0x3c02] = 0
        self.keys('00')
        self.assertEqual(bytes(self.m.memory.ram[0x798:0x7c0]).rstrip(),
                         b'$3\x0301  $00 (0)  $0000 (0)')

    def test_error_overlay_restores_covered_rows_before_incremental_edits(self):
        self.binary()
        m = self.m
        help_row = bytes(m.memory.ram[0x7c0:0x7e8])
        self.keys('I256\r')
        self.assertNotEqual(bytes(m.memory.ram[0x7c0:0x7e8]), help_row)
        self.keys('\x1d')
        self.assertEqual(bytes(m.memory.ram[0x7c0:0x7e8]), help_row)
        self.keys('_CS\r')
        self.assertEqual(m.memory.ram[0xe40], 3)
        bottom = bytes(m.memory.ram[0x798:0x7e8])
        self.keys('B256\r')
        self.keys('2')
        self.assertEqual(bytes(m.memory.ram[0x798:0x7e8]), bottom)

    def test_manual_reservations_blobs_resize_and_types_preserve_bytes(self):
        m = self.m
        original = bytes((i*3)&255 for i in range(1024))
        m.memory.ram[0x3c00:0x4000] = original
        m.command('SPRDEF')
        self.keys('N$3C01\r127\r\rNSNB31\r')
        self.assertEqual(m.memory.ram[0x220], 1)
        self.assertEqual(m.memory.ram[0x221], 0)
        self.assertEqual(m.word(0x200), 0x3c01)
        self.assertEqual(m.word(0x202), 0x3c80)
        self.assertEqual(m.memory.ram[0x223], 3)
        self.assertEqual(m.word(0x229), 0x3c01)
        self.assertEqual(m.word(0x231), 0x3c41)
        self.keys('R$3C60\r16\rCA\r')
        self.assertEqual(m.word(0x231), 0x3c60)
        self.assertEqual(m.word(0x233), 16)
        self.assertEqual(m.memory.ram[0x235], 2)
        self.assertEqual(m.memory.ram[0xe40], 2)  # ASM opens the hex view
        self.assertEqual(bytes(m.memory.ram[0x3c01:0x3c80]), original[1:128])
        before_resize = bytes(m.memory.ram[0x3c00:0x3f00])
        self.keys('__R$3C00\r$300\r')
        self.assertEqual(m.word(0x200), 0x3c00)
        self.assertEqual(m.word(0x202), 0x3f00)
        self.assertEqual(bytes(m.memory.ram[0x3c00:0x3f00]), before_resize)

    def test_basic_bounds_are_read_only_and_deletion_is_confirmed(self):
        self.sprite()
        m = self.m
        self.keys('__R')
        self.assertEqual(m.word(0x200), 0x3c00)
        self.assertEqual(m.word(0x202), 0x3e00)
        self.assertEqual(m.cpu.pc, m.labels['be_wait'])
        self.keys('\x14N')
        self.assertEqual(m.memory.ram[0x220], 1)
        self.keys('\x14Y')
        self.assertEqual(m.memory.ram[0x220], 0)
        self.assertEqual(m.memory.ram[0x223], 0)
        self.assertEqual(m.memory.ram[0xbd2], 2)  # pages stay protected until NEW

    def test_cancelled_or_failed_new_reservation_keeps_previous_selection(self):
        self.m.command('RESERVE $3C00,$200')
        self.m.command('SPRDEF')
        self.keys('N_')
        self.assertEqual(self.m.memory.ram[0xe41],0)
        self.keys('N$3C00\r256\r')  # overlaps existing reservation
        self.assertEqual(self.m.memory.ram[0xe41],0)
        self.assertEqual(self.m.memory.ram[0x220],1)
        self.keys('N$C000\r256\r')
        self.assertEqual(self.m.memory.ram[0xe41],1)
        self.assertEqual(self.m.memory.ram[0x220],3)

    def test_hex_entry_navigation_initialization_and_short_last_word(self):
        self.binary()
        m = self.m
        m.memory.ram[0x3d2c] = 0x73
        self.keys('A5 0,FF\r')
        self.assertEqual(bytes(m.memory.ram[0x3c00:0x3c03]), b'\xa5\0\xff')
        self.assertEqual(m.word(0xe4c), 3)
        self.keys('I$55\r')
        self.assertEqual(bytes(m.memory.ram[0x3c00:0x3d2c]), b'\x55'*300)
        self.assertEqual(m.memory.ram[0x3d2c], 0x73)
        self.keys('\x11'*35)
        self.assertGreater(m.word(0xe4a), 0)
        self.assertLess(m.word(0xe4c), 300)
        self.keys('\x1d'*20)
        self.assertEqual(m.word(0xe4c), 299)
        self.assertIn(b'$0055', bytes(m.memory.ram[0x798:0x7c0]))
        self.keys('TB')  # type change keeps the hex editor and selected data
        self.assertEqual(m.memory.ram[0xe40], 2)

    def test_hires_multicolor_pixels_hardware_and_unused_byte(self):
        self.sprite()
        m = self.m
        m.memory.ram[0x3c00:0x3c40] = bytes(64)
        self.keys('2\x1d\x1d\x1d\x112')
        self.assertEqual(m.memory.ram[0x3c00], 0x80)
        self.assertEqual(m.memory.ram[0x3c03], 0x10)
        self.assertEqual(bytes(m.memory.ram[0x7f8:0x7fc]), bytes((0x31,0x32,0x30,0x30)))
        self.assertEqual((m.memory.ram[0xd000],m.memory.ram[0xd001]), (64,74))
        self.assertEqual(m.memory.ram[0xd015], 15)
        self.assertEqual(m.memory.ram[0xd01c], 0)
        self.keys('T\x9d\x9134\x1d2')
        self.assertEqual(m.memory.ram[0x3c00], 0xe0)
        self.assertEqual(m.memory.ram[0xd01c], 12)
        self.assertEqual(m.memory.ram[0xd017], 8)
        self.assertEqual(m.memory.ram[0xd01d], 8)
        self.assertEqual(bytes(m.memory.ram[0xc00:0xc40]), bytes(m.memory.ram[0x3c00:0x3c40]))
        self.assertEqual(m.memory.ram[0xd800+2*40+2], 9)
        self.assertEqual(m.memory.ram[0xd800+2*40+4], 7)
        self.keys('B$AA\rI3')
        self.assertEqual(bytes(m.memory.ram[0x3c00:0x3c3f]), b'\x55'*63)
        self.assertEqual(m.memory.ram[0x3c3f], 0xaa)
        self.keys('TI2')
        self.assertEqual(bytes(m.memory.ram[0x3c00:0x3c3f]), b'\xff'*63)
        self.assertEqual(m.memory.ram[0x3c3f], 0xaa)

    def test_per_sprite_color_picker_including_zero_and_cancel(self):
        self.sprite()
        m = self.m
        before = bytes(m.memory.ram[0x3c00:0x3c40])
        self.keys('C20\r')
        self.assertEqual(m.memory.ram[0x22e], 0)
        self.assertEqual(m.memory.ram[0xd029], 0)
        self.keys('C1\x9d\r')
        self.assertEqual(m.memory.ram[0x22e], 15)
        self.assertEqual(m.memory.ram[0xd800+2*40+2], 15)
        self.keys('TC37\rC4A\r')
        self.assertEqual(m.memory.ram[0x22f], 0xa7)
        self.keys('C29_')
        self.assertEqual(m.memory.ram[0x22e], 15)
        self.assertEqual(bytes(m.memory.ram[0x3c00:0x3c40]), before)

    def test_exact_binary_save_and_bounded_short_long_empty_loads(self):
        self.sprite()
        m = self.m
        data = bytes(range(64))
        m.memory.ram[0x3c00:0x3c40] = data
        self.keys('SFACE\r')
        self.assertEqual(m.files['FACE.BIN'], data)
        m.files['SHORT.BIN'] = b'\x80\0\xff'
        self.keys('LSHORT\r')
        self.assertEqual(bytes(m.memory.ram[0x3c00:0x3c40]), b'\x80\0\xff'+data[3:])
        m.files['LONG.BIN'] = bytes(range(100))
        m.memory.ram[0x3c40] = 0x77
        self.keys('LLONG\r')
        self.assertEqual(bytes(m.memory.ram[0x3c00:0x3c40]), data)
        self.assertEqual(m.memory.ram[0x3c40], 0x77)
        m.files['EMPTY.BIN'] = b''
        self.keys('LEMPTY\r')
        self.assertEqual(bytes(m.memory.ram[0x3c00:0x3c40]), data)
        self.keys('LMISSING\r')
        self.assertEqual(m.cpu.pc, m.labels['be_wait'])
        self.assertIsNone(m.channel)
        self.assertFalse(m.input_channel or m.output_channel)

    def test_f5_preserves_basic_draft_history_selection_and_vic(self):
        m = self.m
        m.command('10 PRINT 7');m.command('20 PRINT 8');m.command('BASIC')
        self.keys('\rXYZ')
        draft = bytes(m.memory.ram[0xa60:0xb00])
        pane = bytes(m.memory.ram[0x748:0x7e8])
        colors = bytes(m.memory.ram[0xdb48:0xdbe8])
        m.memory.ram[0xd015] = 0x80
        m.memory.ram[0xd027] = 3
        self.keys('\x87N$3C00\r256\r\rNS\r2\x88')
        self.assertEqual(bytes(m.memory.ram[0xa60:0xb00]), draft)
        self.assertEqual(bytes(m.memory.ram[0x748:0x7e8]), pane)
        self.assertEqual(bytes(m.memory.ram[0xdb48:0xdbe8]), colors)
        self.assertEqual(m.word(0x3cf), 10)
        self.assertEqual(m.memory.ram[0xd015], 0x80)
        self.assertEqual(m.memory.ram[0xd027], 3)
        self.assertEqual(m.memory.ram[0x2f7], 0)
        self.assertEqual(m.memory.bank, 3)

    def test_f5_inside_input_retains_pending_command_and_response(self):
        m = self.m
        m.command('10 PRINT 7');m.command('BASIC')
        self.keys('_INPUT A$,B:PRINT A$;B\rHELLO\x87\x88,12\r')
        self.assertIn(b'HELLO 12 ', m.output)
        self.assertEqual(m.cpu.pc, m.labels['editor_wait'])
        self.keys('INPUT A$:PRINT 1/0\rWORLD\x87\x88\r')
        self.assertEqual(bytes(m.memory.ram[0xa60:0xa60+m.memory.ram[0x3cc+15]]),
                         b'INPUT A$:PRINT 1/0')

    def test_source_v2_roundtrip_restores_metadata_bytes_and_protection(self):
        self.sprite()
        m = self.m
        self.keys('T2B99\rC27\r\x88')
        m.command('10 PRINT 42')
        m.command('SAVE "FULL"')
        saved = bytes(m.files['FULL'])
        names, lines = loads(saved)
        self.assertEqual(saved[8], 2)
        self.assertEqual(lines.reservations, (Reservation(0x3c00,512,True),))
        self.assertEqual(lines.blobs[0].data[63], 99)
        self.assertTrue(lines.blobs[0].multicolor)
        self.assertEqual(dumps(names, lines), saved)
        m.command('NEW')
        m.memory.ram[0x3c00:0x3e00] = b'\x73'*512
        self.assertNotIn('?', m.command('LOAD "FULL"'))
        self.assertEqual(bytes(m.memory.ram[0x3c00:0x3c40]), lines.blobs[0].data)
        self.assertEqual(bytes(m.memory.ram[0x3c40:0x3e00]), b'\x73'*(512-64))
        self.assertEqual(m.memory.ram[0x223], 1)
        self.assertEqual(m.memory.ram[0x22d], 0x81)
        self.assertIn(' 42 ', m.command('RUN'))
        self.assertNotIn('?', m.command('PRINT FRE()'))
        self.assertEqual(m.memory.ram[0x223], 1)
        self.assertNotIn('?', m.command('CLEAN'))
        self.assertEqual(m.memory.ram[0x223], 1)
        self.assertNotIn('?', m.command('VERIFY "FULL"'))

    def test_host_v2_import_and_crc_failure_leave_original_metadata_and_data(self):
        m = self.m
        names, lines = text_program('10 PRINT 5')
        lines = ProgramLines(lines, reservations=[Reservation(0xc001,200)],
                             blobs=[Blob(0,0xc003,bytes(range(64)),'SPR',True,(2,3,4,5)),
                                    Blob(0,0xc083,b'ASSEMBLED','ASM')])
        m.files['HOST'] = dumps(names, lines)
        self.assertNotIn('?',m.command('LOAD "HOST"'))
        self.assertEqual(bytes(m.memory.ram[0xc003:0xc043]), bytes(range(64)))
        self.assertEqual(bytes(m.memory.ram[0xc083:0xc08c]), b'ASSEMBLED')
        old = self.metadata()
        raw = bytes(m.memory.ram[0xc000:0xc100])
        bad = bytearray(m.files['HOST']);bad[-1] ^= 1;m.files['BAD'] = bad
        self.assertIn('?SYNTAX ERROR',m.command('LOAD "BAD"'))
        self.assertEqual(self.metadata(), old)
        self.assertEqual(bytes(m.memory.ram[0xc000:0xc100]), raw)
        self.assertIn(' 5 ',m.command('RUN'))

    def test_reservation_prefix_prevents_source_allocation_in_low_blob_pages(self):
        names, lines = text_program('10 PRINT 42\n20 A=1')
        lines = ProgramLines(lines,reservations=[Reservation(0x2c00,0x100)],
                             blobs=[Blob(0,0x2c00,bytes(range(64)),'SPR')])
        self.m.files['LOW'] = dumps(names,lines)
        self.assertNotIn('?',self.m.command('LOAD "LOW"'))
        self.assertEqual(bytes(self.m.memory.ram[0x2c00:0x2c40]),bytes(range(64)))
        self.assertGreaterEqual(self.m.state('head'),0x2d00)
        self.assertIn(' 42 ',self.m.command('RUN'))

    def test_all_pixels_match_source_bits_in_both_modes(self):
        self.sprite()
        m = self.m
        for row in range(21):
            value = (1 << 23) | (1 << row)
            m.memory.ram[0x3c00+row*3:0x3c03+row*3] = value.to_bytes(3,'big')
        self.keys('C27\r')
        for row in range(21):
            value = int.from_bytes(m.memory.ram[0x3c00+row*3:0x3c03+row*3],'big')
            for x in range(24):
                self.assertEqual(m.memory.ram[0xd800+(row+2)*40+x+2],
                                 7 if value & (1 << (23-x)) else 0)
        self.keys('T')
        mapping = (0,1,7,9)
        for row in range(21):
            value = int.from_bytes(m.memory.ram[0x3c00+row*3:0x3c03+row*3],'big')
            for x in range(12):
                color = mapping[(value >> ((11-x)*2)) & 3]
                self.assertEqual(list(m.memory.ram[0xd800+(row+2)*40+x*2+2:
                                                  0xd800+(row+2)*40+x*2+4]), [color,color])

    def test_native_v2_rejects_invalid_metadata_before_writing_blob_bytes(self):
        import binascii
        from ab64.tokens import Names, word
        data = bytearray(dumps(Names(), ProgramLines({},
            reservations=[Reservation(0x3c00,256)],
            blobs=[Blob(0,0x3c00,bytes(range(64)),'SPR')])))
        # Empty v2 source: reservation count 10, descriptor 11, blob count 20, blob 21.
        variants = []
        for offset, value in ((10,9),(15,2),(20,17),(21,8),(26,0xff),(24,63),(23,0xd0)):
            bad = bytearray(data);bad[offset] = value
            bad[-2:] = word(binascii.crc_hqx(bad[:-2],65535));variants.append(bad)
        variants += [data[:n] for n in (1,9,14,18,26,len(data)-1)]
        m = self.m
        m.command('10 PRINT 42')
        m.memory.ram[0x3c00:0x3c40] = b'\x77'*64
        old = self.metadata()
        for index, bad in enumerate(variants):
            with self.subTest(index=index):
                m.files['BAD'] = bad
                self.assertIn('?',m.command('LOAD "BAD"'))
                self.assertEqual(self.metadata(),old)
                self.assertEqual(bytes(m.memory.ram[0x3c00:0x3c40]),b'\x77'*64)
                self.assertIn('10 PRINT 42',m.command('LIST'))


class BinaryContainerTests(unittest.TestCase):
    def test_v1_is_unchanged_and_v2_metadata_survives_normal_codec_calls(self):
        names, lines = text_program('10 PRINT 42')
        simple = dumps(names,lines)
        self.assertEqual(simple[8:10],b'\1\0')
        self.assertEqual(dumps(*loads(simple)),simple)
        rich = ProgramLines(lines,reservations=[Reservation(0x3c01,255)],
                            blobs=[Blob(0,0x3c03,b'\0\xff\x80'),
                                   Blob(0,0x3c40,bytes(range(64)),'SPR',True,(1,2,3,4))])
        data = dumps(names,rich)
        self.assertEqual(data[8:10],b'\2\0')
        nn,ll = loads(data)
        self.assertEqual(ll.reservations,rich.reservations)
        self.assertEqual(ll.blobs,rich.blobs)
        self.assertEqual(dumps(nn,ll),data)

    def test_bad_metadata_and_truncation_are_rejected(self):
        from ab64.tokens import Names, SourceError
        n = Names()
        bad = [ProgramLines({},reservations=[Reservation(0x1400,256)]),
               ProgramLines({},reservations=[Reservation(0x3c01,255,True)]),
               ProgramLines({},reservations=[Reservation(0x3c00,128),Reservation(0x3c40,64)]),
               ProgramLines({},reservations=[Reservation(0x3c00,256)],blobs=[Blob(0,0x3c00,b'X','SPR')]),
               ProgramLines({},reservations=[Reservation(0x3c00,256)],blobs=[Blob(1,0x3c00,b'X')]),
               ProgramLines({},reservations=[Reservation(0x3c00,256)],blobs=[Blob(0,0x3c00,b'X','BIN',True)])]
        for value in bad:
            with self.assertRaises(SourceError):dumps(n,value)
        data = dumps(n,ProgramLines({},reservations=[Reservation(0x3c00,256)],
                                   blobs=[Blob(0,0x3c00,bytes(range(64)),'SPR')]))
        for length in range(len(data)):
            with self.assertRaises(SourceError):loads(data[:length])
