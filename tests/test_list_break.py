"""LIST polls both KERNAL STOP and the cartridge's pending break flag."""
import unittest
from machine import Machine


class ListBreakTests(unittest.TestCase):
    def test_stop_aborts_listing_in_stock_and_split_editors(self):
        for split in (False, True):
            with self.subTest(split=split):
                m = Machine().boot()
                for n in range(10, 211, 10):
                    m.command(f'{n} PRINT {n}')
                if split:
                    m.command('BASIC')
                    m.input.extend(b'_');m.pump()
                step = m.step
                calls = 0

                def stop_after_three():
                    nonlocal calls
                    if m.cpu.pc == 0xffe1 and m.memory.ram[1] & 2:
                        calls += 1
                        if calls == 4:
                            m.cpu.a = 0
                            m.cpu.p |= 2
                            m.rts()
                            return True
                    return step()

                m.step = stop_after_three
                start = len(m.output)
                m.input.extend(b'LIST\r');m.pump()
                output = bytes(m.output[start:])
                self.assertIn(b'30 PRINT 30', output)
                self.assertNotIn(b'40 PRINT 40', output)
                self.assertEqual(m.memory.ram[0x77], 0)
                self.assertEqual(m.memory.ram[0x3cc], int(split))
                m.step = step
                if split:
                    m.input.extend(b'PRINT 7\r');m.pump()
                    self.assertIn(b' 7 ', m.output)
                else:
                    self.assertIn(' 7 ', m.command('PRINT 7'))

    def test_pending_break_aborts_before_printing_the_next_line(self):
        m = Machine().boot()
        for n in range(10, 51, 10):
            m.command(f'{n} PRINT {n}')
        step = m.step
        visited = 0

        def pending_after_one():
            nonlocal visited
            if m.cpu.pc == m.labels['list_line']:
                visited += 1
                if visited == 2:
                    m.memory.ram[0x77] = 1
            return step()

        m.step = pending_after_one
        text = m.command('LIST')
        self.assertIn('10 PRINT 10', text)
        self.assertNotIn('20 PRINT 20', text)
        self.assertEqual(m.memory.ram[0x77], 0)
