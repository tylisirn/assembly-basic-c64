"""Screen submission regression: Enter must advance before command processing."""
import unittest
from machine import Machine


class EditorTests(unittest.TestCase):
    def setUp(self):
        self.m = Machine().boot()

    def test_enter_advances_after_numbered_entry_deletion_and_empty_input(self):
        m = self.m
        for source in ('10 PRINT 7', '20 PRINT 8', '10', ''):
            with self.subTest(source=source):
                m.memory.ram[0xd3] = 17
                row = m.memory.ram[0xd6]
                self.assertEqual(m.command(source, include_input_newline=True), '\r')
                self.assertEqual(m.memory.ram[0xd3], 0)
                self.assertEqual(m.memory.ram[0xd6], min(row + 1, 24))
        self.assertIn('20 PRINT 8', m.command('LIST'))
        self.assertNotIn('10 PRINT', m.command('LIST'))

    def test_command_output_and_submission_errors_start_after_enter(self):
        m = self.m
        for source, prefix in (('PRINT 7', '\r 7 '),
                               ('10 A=(', '\r?SYNTAX ERROR')):
            with self.subTest(source=source):
                m.memory.ram[0xd3] = 17
                start = len(m.services)
                self.assertTrue(m.command(source, include_input_newline=True).startswith(prefix))
                output = [a for pc, mode, a, x, y in m.services[start:] if pc == 0xffd2]
                self.assertEqual(output[0], 13)
        self.assertIn('10 A = (', m.command('LIST'))

    def test_console_api_preserves_program_newlines_without_echoing_enter(self):
        m = self.m
        self.assertEqual(m.command('10 PRINT 7'), '')
        self.assertTrue(m.command('PRINT').startswith('\r'))
        self.assertTrue(m.command('PRINT 7').startswith(' 7 '))


ED = 0x3cc
TEXT = 0xa60
PANE = 0x748


class SplitEditorTests(unittest.TestCase):
    def setUp(self):
        self.m = Machine().boot()

    def keys(self, keys):
        self.m.input.extend(keys.encode('latin-1'))
        self.m.pump()

    def screen(self, start=0x400, count=1000):
        return bytes(self.m.memory.ram[start:start+count])

    def draft(self):
        return bytes(self.m.memory.ram[TEXT:TEXT+self.m.memory.ram[ED+15]])

    def test_open_copy_submit_delete_and_exit(self):
        m = self.m
        m.command('10 PRINT 7')
        m.command('20 PRINT 8')
        m.command('BASIC')
        self.assertEqual(m.memory.ram[ED:ED+3], bytes((1, 0, 0)))
        self.assertEqual(m.word(0x326), m.labels['editor_output_gate'])
        self.keys('\r')
        self.assertEqual(self.draft(), b'10 PRINT 7')
        self.assertEqual(m.memory.ram[ED+16], 10)
        self.keys('\x14'+'9'+'\r')
        self.assertEqual(self.draft(), b'')
        self.keys('20\r')
        self.assertEqual(self.draft(), b'')
        self.keys('\x88')
        self.assertEqual(m.memory.ram[ED], 0)
        self.assertEqual(m.word(0x326), 0xf1ca)
        self.assertEqual(self.screen(), b' '*1000)
        listing = m.command('LIST')
        self.assertIn('10 PRINT 9', listing)
        self.assertNotIn('20 PRINT', listing)

    def test_wrapped_source_aligns_past_number_and_controls_are_literal(self):
        m = self.m
        m.command('370 REM '+ 'X'*67)
        m.command('380 PRINT "A'+chr(147)+'B"')
        m.command('BASIC')
        row = self.screen(0x428, 40)
        self.assertEqual(bytes(b & 127 for b in row[:4]), b' '*4)
        self.assertEqual(row[4] & 127, ord('X') & 63)
        self.keys('\x11\r')
        self.assertEqual(self.draft(), b'380 PRINT "A\x93B"')
        self.assertIn(0xd3, self.screen(PANE, 40))

    def test_scrolls_five_source_lines_and_preserves_bookmarks(self):
        m = self.m
        for line in range(10, 311, 10):
            m.command(f'{line} PRINT {line}')
        m.command('BASIC')
        self.keys('\x11'*20)
        self.assertEqual(m.word(ED+3), 210)
        self.assertEqual(m.word(ED+5), 60)
        self.keys('\x91'*16)
        self.assertEqual(m.word(ED+3), 50)
        self.assertEqual(m.word(ED+5), 10)
        self.keys('\x11'*20+'\x88')
        selected, top = m.word(ED+3), m.word(ED+5)
        m.command('BASIC')
        self.assertEqual((m.word(ED+3), m.word(ED+5)), (selected, top))
        self.keys('_PRINT 123\r')
        self.assertEqual((m.word(ED+3), m.word(ED+5)), (selected, top))

    def test_focus_switch_discards_draft_and_commands_have_no_ready(self):
        m = self.m
        m.command('10 PRINT 7')
        m.command('BASIC')
        self.keys('\r')
        self.assertTrue(self.draft())
        self.keys('_')
        self.assertEqual(self.draft(), b'')
        self.assertEqual(m.memory.ram[ED+1], 0)
        self.keys('_PRINT 123')
        start = len(m.output)
        self.keys('\r')
        self.assertNotIn(b'READY.', m.output[start:])
        self.assertIn(b' 123 ', m.output[start:])
        self.assertEqual(m.memory.ram[ED+1], 1)
        self.assertEqual(self.draft(), b'')
        self.assertIn(b'123', self.screen(PANE, 160))
        self.keys('QUIT\r')
        self.assertEqual(m.memory.ram[ED], 0)

    def test_run_exits_clears_and_executes(self):
        m = self.m
        m.command('10 PRINT 77')
        m.command('BASIC')
        start = len(m.output)
        self.keys('_RUN\r')
        out = bytes(m.output[start:])
        self.assertIn(b'\x93 77 ', out)
        self.assertEqual(m.memory.ram[ED], 0)
        self.assertEqual(m.memory.bank, 0)
        self.assertEqual(m.word(0x326), 0xf1ca)

    def test_insert_overwrite_literal_and_bounded_cursor(self):
        m = self.m
        m.command('BASIC')
        self.keys('_ABCD\x9d\x9dX')
        self.assertEqual(self.draft(), b'ABXCD')
        self.keys('\x94Z')
        self.assertEqual(self.draft(), b'ABXZD')
        self.assertEqual(m.memory.ram[0xdb48+4], 0)
        self.keys('\x05\x93\x11')  # literal + overwrite replaces both cells
        self.assertEqual(self.draft(), b'ABXZ\x93\x11')
        pos = m.memory.ram[ED+16]
        self.assertEqual(m.memory.ram[PANE+pos], 0x8c)
        self.assertEqual(m.memory.ram[0xdb48+pos], 3)
        self.assertEqual(m.memory.ram[ED+2], 1)
        self.keys('\x94\x93')  # INS changes writing policy without disabling literal
        self.assertEqual(self.draft(), b'ABXZ\x93\x11\x93')
        self.assertEqual(m.memory.ram[ED+2], 0)
        self.keys('\x05')
        before = self.draft()
        self.keys('\x93\x12')
        self.assertEqual(self.draft(), before)
        listing = self.screen(0x400, 840)
        self.keys('\x11'*10+'\x1d'*170)
        self.assertEqual(m.memory.ram[ED+16]+m.memory.ram[ED+17], 159)
        self.assertEqual(self.screen(0x400, 840), listing)
        self.keys('\x91'*10+'\x9d'*170)
        self.assertEqual(m.memory.ram[ED+16], 0)

    def test_errors_retain_source_and_put_cursor_at_line_start(self):
        m = self.m
        m.command('BASIC')
        self.keys('_10 A=(\r')
        self.assertEqual(self.draft(), b'10 A=(')
        self.assertEqual(m.memory.ram[ED+16], 0)
        self.assertIn(b'SYNTAX ERROR', m.output)
        self.assertEqual(self.screen(0x720, 7), bytes((ord(c) & 63) | 128 for c in '?SYNTAX'))
        self.assertEqual(bytes(b & 127 for b in self.screen(PANE, 6)), bytes((ord(c) & 63) if c >= '@' else ord(c) for c in '10 A=('))
        self.keys('_'+'_PRINT 1/0\r')
        self.assertEqual(self.draft(), b'PRINT 1/0')
        self.assertEqual(m.memory.ram[ED+16], 0)
        self.assertIn(b'DIVISION BY ZERO', m.output)
        self.assertEqual(m.memory.ram[ED], 1)

    def test_help_restores_draft_screen_and_bookmarks(self):
        m = self.m
        m.command('10 PRINT 7')
        m.command('BASIC')
        self.keys('\rXYZ')
        draft = self.draft()
        pane = self.screen(PANE, 160)
        selected, top = m.word(ED+3), m.word(ED+5)
        self.keys('\x85')
        self.assertEqual(m.memory.ram[ED+29], 1)
        self.assertEqual(self.screen(0x400, 8), bytes(ord(c) & 63 for c in 'ASSEMBLY'))
        self.keys(' ')
        self.assertEqual(m.memory.ram[ED+29], 0)
        self.assertEqual(self.draft(), draft)
        self.assertEqual(self.screen(PANE, 160), pane)
        self.assertEqual((m.word(ED+3), m.word(ED+5)), (selected, top))
        self.keys('\x85\x88')
        self.assertEqual(m.memory.ram[ED], 0)

    def test_output_scrolls_only_four_rows_and_mutations_refresh_listing(self):
        m = self.m
        m.command('10 PRINT 7')
        m.command('BASIC')
        self.keys('_')
        listing = self.screen(0x400, 840)
        self.keys('FOR I=1 TO 10:PRINT I:NEXT I\r')
        self.assertEqual(self.screen(0x400, 840), listing)
        self.assertIn(b'10', self.screen(PANE, 160))
        self.keys('NEW\r')
        self.assertEqual(self.screen(0x400, 800), b' '*800)
        self.keys('30 PRINT 5\r')
        self.assertEqual(m.word(ED+3), 30)
        self.keys('CLEAN\r')
        self.assertEqual(m.word(ED+3), 30)
        self.assertEqual(m.memory.ram[ED], 1)

    def test_exact_keywords_do_not_reserve_variable_names(self):
        m = self.m
        self.assertNotIn('?', m.command('BASIC=7:QUIT=8:PRINT BASIC;QUIT'))
        m.command('  basic  ')
        self.assertEqual(m.memory.ram[ED], 1)
        self.keys('_quit  \r')
        self.assertEqual(m.memory.ram[ED], 0)

    def test_direct_input_uses_bounded_pane_and_retains_command_on_error(self):
        m = self.m
        m.command('10 PRINT 7')
        m.command('BASIC')
        self.keys('_')
        listing = self.screen(0x400, 840)
        self.keys('INPUT A$,B:PRINT A$;B\r')
        self.assertEqual(m.cpu.pc, m.labels['editor_input_wait'])
        self.assertFalse(m.cpu.p & 4)
        self.keys('HELLO\x85 ,12\r')
        self.assertEqual(m.cpu.pc, m.labels['editor_wait'])
        self.assertIn(b'HELLO 12 ', m.output)
        self.assertEqual(self.screen(0x400, 840), listing)
        self.keys('INPUT A$:PRINT 1/0\r')
        self.keys('WORLD\r')
        self.assertEqual(self.draft(), b'INPUT A$:PRINT 1/0')
        self.assertEqual(m.memory.ram[ED+16], 0)
        self.keys('_'+'_INPUT A$\r'+'\x88')
        self.assertEqual(m.memory.ram[ED], 0)
        self.assertEqual(m.word(0x324), 0xf157)

    def test_four_row_capacity_and_scrolling_from_a_direct_output_position(self):
        m = self.m
        m.command('BASIC')
        self.keys('_PRINT 123\r')
        self.keys('A'*120)
        self.assertEqual(self.draft(), b'A'*120)
        self.assertLess(m.memory.ram[ED+17], 40)
        self.keys('_'+'_'+'A'*160)
        self.assertEqual(self.draft(), b'A'*160)
        listing = self.screen(0x400, 840)
        self.keys('B')
        self.assertEqual(self.draft(), b'A'*160)
        self.assertEqual(self.screen(0x400, 840), listing)
        self.keys('\x94B')
        self.assertEqual(self.draft(), b'A'*159+b'B')
        self.keys('\x85 \x88')
        self.assertEqual(m.memory.ram[ED], 0)

    def test_output_gate_preserves_registers_flags_and_user_zero_page(self):
        m = self.m
        m.command('BASIC')
        self.keys('_')
        c, ram = m.cpu, m.memory.ram
        saved = (c.pc, c.sp)
        ram[0xfb:0xff] = bytes.fromhex('12345678')
        c.pc=m.labels['editor_output_gate']; c.sp=0xfd
        c.stPushWord(0x6ff); c.a=ord('X'); c.x=17; c.y=23; c.p=0x25
        for _ in range(1000):
            if c.pc==0x700: break
            m.step()
        else: self.fail('Output hook did not return')
        self.assertEqual((c.a, c.x, c.y, c.p & 0xcf), (ord('X'), 17, 23, 5))
        self.assertEqual(ram[0xfb:0xff], bytes.fromhex('12345678'))
        self.assertEqual((m.memory.bank, ram[1]&7), (3, 7))
        c.pc,c.sp=saved

    def test_pane_clear_controls_do_not_discard_a_failed_command(self):
        m = self.m
        m.command('BASIC')
        self.keys('_PRINT CHR$(147):PRINT 1/0\r')
        self.assertEqual(self.draft(), b'PRINT CHR$(147):PRINT 1/0')
        self.assertEqual(m.memory.ram[ED+16], 0)
        self.assertEqual(bytes(b & 127 for b in self.screen(PANE, 5)), bytes(ord(c) & 63 for c in 'PRINT'))

    def test_failed_load_and_allocation_keep_editable_source(self):
        m = self.m
        m.command('10 PRINT 7')
        m.files['BAD'] = bytearray(b'NOT AN AB CONTAINER')
        m.command('BASIC')
        self.keys('_LOAD "BAD",8\r')
        self.assertEqual(self.draft(), b'LOAD "BAD",8')
        self.assertEqual(m.word(ED+3), 10)
        m.memory.ram[0xb00:0xb02] = bytes(2)  # deterministic allocator exhaustion
        self.keys('_'+'_20 REM '+ 'X'*100+'\r')
        self.assertEqual(self.draft(), b'20 REM '+b'X'*100)
        self.assertEqual(m.memory.ram[ED+16], 0)
        self.keys('\x88')
        listing=m.command('LIST')
        self.assertIn('10 PRINT 7', listing)
        self.assertNotIn('20 REM', listing)

    def test_overlong_imported_line_is_not_silently_truncated(self):
        from ab64.cli import text_program
        from ab64.container import dumps
        m = self.m
        m.files['LONG'] = bytearray(dumps(*text_program('10 REM '+'Z'*180)))
        m.command('LOAD "LONG",8')
        m.command('BASIC')
        self.keys('\r')
        self.assertEqual(self.draft(), b'')
        self.assertEqual(m.memory.ram[ED+30], 1)
        self.keys('\x88')
        self.assertIn('Z'*180, m.command('LIST'))

    def record_video_writes(self):
        from machine import Memory

        class RecordingMemory(Memory):
            def __setitem__(self, address, value):
                if 0x400 <= address < 0x7e8 or 0xd800 <= address < 0xdbe8:
                    self.video_writes.append((address, value))
                super().__setitem__(address, value)

        memory = self.m.memory
        memory.__class__ = RecordingMemory
        memory.video_writes = []
        return memory.video_writes

    def test_selection_highlights_only_digits_and_never_reformats_source(self):
        m = self.m
        m.command('10 REM '+ 'A'*65)
        m.command('20 PRINT 2')
        m.command('BASIC')
        self.assertEqual(self.screen(0x400, 2), b'\xb1\xb0')
        self.assertEqual(self.screen(0x402, 1), b' ')
        self.assertEqual(self.screen(0x403, 4), bytes((18, 5, 13, 32)))
        self.assertEqual(self.screen(0x428, 3), b' '*3)
        self.assertEqual(self.screen(0x42b, 1), b'\x01')
        writes = self.record_video_writes()
        before_services = len(m.services)
        self.keys('\x11')
        listing_writes = [(p, b) for p, b in writes if 0x400 <= p < 0x720]
        self.assertEqual(listing_writes, [(0x400, 49), (0x401, 48),
                                         (0x450, 178), (0x451, 176)])
        self.assertFalse(any(0xd800 <= p < 0xdb20 for p, _ in writes))
        self.assertFalse(any(pc == 0xffd2 for pc, *_ in m.services[before_services:]))
        writes.clear()
        self.keys('\x11')  # last program line, so no redraw or cursor repaint
        self.assertEqual(writes, [])
        self.keys('\x91')
        self.assertEqual(self.screen(0x400, 2), b'\xb1\xb0')

    def test_focus_copy_and_source_preserving_commands_do_not_redraw_listing(self):
        m = self.m
        m.command('10 PRINT 7')
        m.command('20 PRINT 8')
        m.command('BASIC')
        writes = self.record_video_writes()
        self.keys('\r')
        self.assertEqual(self.draft(), b'10 PRINT 7')
        self.assertEqual(self.screen(0x400, 2), b'\xb1\xb0')
        self.assertEqual([p for p, _ in writes if p < 0x720], [])
        writes.clear()
        self.keys('_')
        self.assertEqual([p for p, _ in writes if p < 0x720], [])
        self.keys('_')
        for command in ('PRINT 123', 'PRINT 1/0', 'CLR', 'CLEAN'):
            with self.subTest(command=command):
                # Discard an error draft before the next direct command.
                self.keys('__')
                writes.clear()
                self.keys(command+'\r')
                self.assertFalse(any(0x400 <= p < 0x720 for p, _ in writes))
                self.assertFalse(any(0xd800 <= p < 0xdb20 for p, _ in writes))

    def test_numbered_submissions_select_affected_lines_and_scroll_into_view(self):
        m = self.m
        for number in range(10, 261, 10):
            m.command(f'{number} PRINT {number}')
        m.command('BASIC')
        self.keys('_')
        writes = self.record_video_writes()
        self.keys('10 PRINT 10\r')
        self.assertFalse(any(0x400 <= p < 0x720 for p, _ in writes))
        self.keys('150 PRINT 999\r')
        self.assertEqual(m.word(ED+3), 150)
        self.assertEqual(m.word(ED+5), 10)
        self.assertEqual(self.screen(0x400+14*40, 3), b'\xb1\xb5\xb0')
        self.keys('260 PRINT 999\r')
        self.assertEqual(m.word(ED+3), 260)
        self.assertEqual(m.word(ED+5), 230)
        self.assertEqual(self.screen(0x400+3*40, 3), b'\xb2\xb6\xb0')
        self.keys('260\r')
        self.assertEqual(m.word(ED+3), 250)
        self.assertNotEqual(m.memory.ram[ED+50], 255)
        self.keys('5 PRINT 1\r')
        self.assertEqual(m.word(ED+3), 5)
        self.assertEqual(self.screen(0x400, 1), b'\xb5')
        self.keys('15 A=(\r')
        self.assertEqual(m.word(ED+3), 15)
        self.assertEqual(m.memory.ram[ED+1], 1)
        row = m.memory.ram[ED+50]
        self.assertEqual(self.screen(0x400+row*40, 2), b'\xb1\xb5')
        self.keys('__64000 A=1\r')
        self.assertEqual(m.word(ED+3), 15)  # invalid number leaves selection alone
        self.keys('__17\r')
        self.assertEqual(m.word(ED+3), 20)  # absent deletion selects next survivor
        self.assertFalse(any(0xd800 <= p < 0xdb20 for p, _ in writes))

    def test_unchanged_numbered_submission_can_move_only_number_highlights(self):
        m = self.m
        m.command('10 PRINT 1')
        m.command('20 PRINT 2')
        m.command('BASIC')
        self.keys('_')
        writes = self.record_video_writes()
        self.keys('20\r')  # deletion selects the preceding surviving line
        self.assertEqual(m.word(ED+3), 10)
        self.keys('20 PRINT 2\r')
        self.keys('10 PRINT 1\r')
        writes.clear()
        self.keys('20 PRINT 2\r')
        self.assertEqual(m.word(ED+3), 20)
        self.assertEqual([p for p, _ in writes if p < 0x720],
                         [0x400, 0x401, 0x428, 0x429])

    def test_previous_visible_commands_and_wrapped_lines_can_be_edited(self):
        m = self.m
        m.command('BASIC')
        self.keys('_PRINT 123\r')
        listing = self.screen(0x400, 840)
        self.keys('\x91\x91')  # blank prompt -> output -> original command
        self.assertEqual(self.draft(), b'PRINT 123')
        self.assertEqual(m.memory.ram[ED+16], 0)
        self.keys('\x1d'*8+'\x14'+'4\r')
        self.assertIn(b' 143 ', m.output)
        self.assertEqual(self.screen(0x400, 840), listing)
        self.keys('__REM '+ 'X'*45+'\r')
        self.keys('\x91')  # the preceding physical row continues the command
        self.assertEqual(self.draft(), b'REM '+b'X'*45)
        self.assertEqual(m.memory.ram[ED+16], 40)
        self.keys('\x91')
        self.assertEqual(m.memory.ram[ED+16], 0)
        self.keys('__PRINT CHR$(147):PRINT "'+ 'X'*45+'"\r')
        self.keys('\x91\x91')  # output wrapping also preserves logical lines
        self.assertEqual(self.draft().strip(), b'X'*45)

    def test_error_returns_to_command_start_at_its_current_screen_row(self):
        m = self.m
        m.command('BASIC')
        self.keys('_PRINT 1\r')
        self.assertEqual(m.memory.ram[ED+17], 80)
        self.keys('A=(\r')
        self.assertEqual((m.memory.ram[ED+17], m.memory.ram[ED+16]), (80, 0))
        self.assertEqual(self.draft(), b'A=(')
        self.keys('\x91\x91')
        self.assertEqual(self.draft(), b'PRINT 1')
        self.keys('\x1d'*6+'\x94'+'2')
        self.assertEqual(self.draft(), b'PRINT 2')
        self.assertEqual(self.screen(PANE+80, 3), b'\x01=(')
        # Editing earlier history must preserve the failed command below it.
        self.keys('\x11\x11')
        self.assertEqual(self.draft(), b'A=(')
        self.keys('\x85 ')
        self.assertEqual(self.draft(), b'A=(')

    def test_input_uses_independent_literal_and_overwrite_modes(self):
        m = self.m
        m.command('BASIC')
        self.keys('_INPUT A$:PRINT LEN(A$)\r')
        self.keys('AB\x9d\x94\x05\x93\x05\r')
        self.assertIn(b' 2 ', m.output)
        self.assertEqual(m.memory.ram[ED+2], 1)
        self.assertEqual(m.memory.ram[0xfb3], 0)

    def test_bidirectional_scroll_moves_rows_without_touching_color_ram(self):
        m = self.m
        for number in range(10, 311, 10):
            m.command(f'{number} PRINT {number}')
        m.command('BASIC')
        self.keys('\x11'*19)
        before = bytes(b & 127 for b in self.screen(0x400, 800))
        colors = self.screen(0xd800, 800)
        writes = self.record_video_writes()
        self.keys('\x11')
        after = bytes(b & 127 for b in self.screen(0x400, 800))
        self.assertEqual(after[:600], before[200:])
        self.assertEqual(self.screen(0xd800, 800), colors)
        self.assertFalse(any(0xd800 <= p < 0xdb20 for p, _ in writes))
        retained_writes = [p for p, _ in writes if 0x400 <= p < 0x658]
        self.assertEqual(len(retained_writes), 600)  # each retained character copied once
        self.assertIn(b'21', after[600:640])
        self.keys('\x91'*15)
        before = bytes(b & 127 for b in self.screen(0x400, 800))
        writes.clear()
        self.keys('\x91')
        after = bytes(b & 127 for b in self.screen(0x400, 800))
        self.assertEqual(after[200:], before[:600])
        self.assertFalse(any(0xd800 <= p < 0xdb20 for p, _ in writes))
        retained_writes = [p for p, _ in writes if 0x4c8 <= p < 0x720]
        self.assertEqual(len(retained_writes), 600)

    def test_wrapped_scroll_restores_partial_lines_and_matches_a_fresh_view(self):
        m = self.m
        for number in range(10, 311, 10):
            # First five BASIC lines occupy ten physical rows. Later lines mix
            # widths, including a clipped line at the bottom of the viewport.
            count = 50 if number <= 50 or number % 30 == 0 else 5
            m.command(f'{number} REM '+ 'X'*count)
        m.command('BASIC')
        while m.word(ED+3) < m.word(ED+7):
            self.keys('\x11')
        before = bytes(b & 127 for b in self.screen(0x400, 800))
        writes = self.record_video_writes()
        self.keys('\x11')
        after = bytes(b & 127 for b in self.screen(0x400, 800))
        self.assertEqual(m.word(ED+5), 60)
        self.assertEqual(after[:400], before[400:])
        self.assertFalse(any(0xd800 <= p < 0xdb20 for p, _ in writes))
        optimized = self.screen(0x400, 800)
        self.keys('\x88')
        m.command('BASIC')
        self.assertEqual(self.screen(0x400, 800), optimized)
        while m.word(ED+3) > 60:
            self.keys('\x91')
        writes.clear()
        self.keys('\x91')
        self.assertEqual(m.word(ED+5), 10)
        self.assertFalse(any(0xd800 <= p < 0xdb20 for p, _ in writes))
        optimized = self.screen(0x400, 800)
        self.keys('\x88')
        m.command('BASIC')
        self.assertEqual(self.screen(0x400, 800), optimized)

    def test_help_uses_petscii_95_and_restores_saved_listing_without_formatting(self):
        m = self.m
        m.command('10 PRINT 7')
        m.command('BASIC')
        listing = self.screen(0x400, 800)
        writes = self.record_video_writes()
        before_services = len(m.services)
        self.keys('\x85')
        self.assertEqual(self.screen(0x400+4*40, 1), b'\x1f')
        self.assertEqual(self.screen(0x400+19*40, 5), bytes(ord(c) & 63 for c in 'PRESS'))
        self.assertFalse(any(0xd800 <= p < 0xdb20 for p, _ in writes))
        self.keys(' ')
        self.assertEqual(self.screen(0x400, 800), listing)
        self.assertFalse(any(pc == 0xffd2 for pc, *_ in m.services[before_services:]))
        self.keys('_INPUT A$,B:PRINT A$;B\r')
        self.keys('AB\x85 \x85 ,12\r')
        self.assertIn(b'AB 12 ', m.output)

    def test_lines_taller_than_the_frame_scroll_without_overlap_or_color_writes(self):
        from ab64.cli import text_program
        from ab64.container import dumps
        m = self.m
        name = 'V'*200
        source = f'10 {name}={name}+{name}+{name}+{name}\n20 PRINT 2\n30 PRINT 3'
        m.files['TALL'] = bytearray(dumps(*text_program(source)))
        m.command('LOAD "TALL",8')
        m.command('BASIC')
        before = self.screen(0x400, 800)
        writes = self.record_video_writes()
        self.keys('\x11')
        self.assertEqual((m.word(ED+3), m.word(ED+5)), (20, 20))
        self.assertEqual(self.screen(0x400, 2), b'\xb2\xb0')
        self.assertFalse(any(0xd800 <= p < 0xdb20 for p, _ in writes))
        writes.clear()
        self.keys('\x91')
        self.assertEqual((m.word(ED+3), m.word(ED+5)), (10, 10))
        self.assertEqual(self.screen(0x400, 800), before)
        self.assertFalse(any(0xd800 <= p < 0xdb20 for p, _ in writes))

    def test_many_scrolls_and_source_changes_match_fresh_viewports(self):
        import random
        m = self.m
        for number in range(10, 411, 10):
            m.command(f'{number} REM '+chr(65+number//10 % 26)*(number % 75))
        m.command('BASIC')
        randomizer = random.Random(95)
        for _ in range(4):
            self.keys(''.join(randomizer.choice(('\x91', '\x11', '\x11')) for _ in range(35)))
            optimized = self.screen(0x400, 800)
            selected, top = m.word(ED+3), m.word(ED+5)
            self.keys('\x88')
            m.command('BASIC')
            self.assertEqual((m.word(ED+3), m.word(ED+5)), (selected, top))
            self.assertEqual(self.screen(0x400, 800), optimized)
        self.keys('_'+f'{m.word(ED+5)} REM '+ 'Z'*100+'\r')
        self.keys('_')
        optimized = self.screen(0x400, 800)
        self.keys('\x88')
        m.command('BASIC')
        self.assertEqual(self.screen(0x400, 800), optimized)

    def test_help_preserves_a_suspended_gosub_for_cont(self):
        m = self.m
        for source in ('10 GOSUB 100', '20 END', '100 STOP', '110 PRINT 7:RETURN'):
            m.command(source)
        m.command('RUN')
        frames = self.screen(0x1000, 512)
        m.command('BASIC')
        self.keys('\x85 \x88')
        self.assertEqual(self.screen(0x1000, 512), frames)
        self.assertIn(' 7 ', m.command('CONT'))

    def test_f3_go_line_is_incremental_and_non_digits_only_cancel_the_prompt(self):
        m = self.m
        for number in range(10, 311, 10):
            m.command(f'{number} PRINT {number}')
        m.command('BASIC')
        self.keys('\rXYZ')
        draft, pane = self.draft(), self.screen(PANE, 160)
        generation = m.word(0xb11)
        self.keys('\x86')
        self.assertEqual(bytes(b & 127 for b in self.screen(0x720, 8)),
                         bytes((7, 15, 32, 12, 9, 14, 5, 32)))
        self.keys('260')
        self.assertEqual((m.word(ED+3), m.word(ED+5)), (260, 230))
        self.assertEqual(m.memory.ram[ED+50], 3)
        self.assertEqual(self.screen(0x400+3*40, 3), b'\xb2\xb6\xb0')
        self.keys('\r')
        self.assertEqual(self.draft(), draft)
        self.assertEqual(self.screen(PANE, 160), pane)
        self.assertEqual(m.word(0xb11), generation)
        self.assertEqual(m.memory.ram[ED+1], 1)
        self.keys('\x86265 ')
        self.assertEqual(m.word(ED+3), 270)
        self.keys('\x86639999\x88')  # overflow ignored; F7 cancels the prompt
        self.assertEqual(m.word(ED+3), 310)
        self.assertEqual(m.memory.ram[ED], 1)
        self.assertEqual(self.draft(), draft)
        self.keys('\x86\x85')  # F1 also only cancels, without opening help
        self.assertEqual(m.memory.ram[ED+29], 0)

    def test_go_line_visible_destination_only_changes_number_cells(self):
        m = self.m
        for number in (10, 20, 30):
            m.command(f'{number} PRINT {number}')
        m.command('BASIC')
        writes = self.record_video_writes()
        self.keys('\x8610\r')
        self.assertFalse(any(0x400 <= p < 0x720 for p, _ in writes))
        writes.clear()
        self.keys('\x8620\r')
        self.assertEqual([p for p, _ in writes if p < 0x720],
                         [0x400, 0x401, 0x428, 0x429])
        self.assertFalse(any(0xd800 <= p < 0xdb20 for p, _ in writes))
        self.assertEqual(m.word(ED+5), 10)

    def test_go_line_and_submission_keep_wrapped_context_and_destination_visible(self):
        m = self.m
        for number in range(10, 311, 10):
            m.command(f'{number} REM '+ 'X'*55)
        m.command('BASIC')
        self.keys('\x86260\r')
        self.assertEqual((m.word(ED+3), m.word(ED+5)), (260, 230))
        self.assertEqual(m.memory.ram[ED+50], 6)
        self.keys('_300 PRINT 1\r')
        self.assertEqual((m.word(ED+3), m.word(ED+5)), (300, 230))
        # Three very tall context lines must not displace the destination.
        from ab64.cli import text_program
        from ab64.container import dumps
        # Native token lines have a 255-byte limit; use long repeated identifiers
        # so the formatter expands a compact token stream beyond the frame.
        name = 'V'*200
        source = (f'10 {name}={name}+{name}+{name}+{name}'
                  '\n20 PRINT 2\n30 PRINT 3\n40 PRINT 4')
        m.files['TALL'] = bytearray(dumps(*text_program(source)))
        self.keys('LOAD "TALL",8\r')
        self.keys('\x8640\r')
        self.assertEqual((m.word(ED+3), m.word(ED+5)), (40, 20))
        self.assertEqual(m.memory.ram[ED+50], 2)

    def test_f3_while_collecting_input_preserves_runtime_fields_and_draft(self):
        m = self.m
        for number in range(10, 311, 10):
            m.command(f'{number} PRINT {number}')
        m.command('BASIC')
        self.keys('_INPUT A$,B:PRINT A$;B\r')
        self.keys('HELLO\x86260\r,12\r')
        self.assertIn(b'HELLO 12 ', m.output)
        self.assertEqual(m.word(ED+3), 260)
        self.assertEqual(m.memory.ram[ED], 1)
