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
