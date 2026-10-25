"""Source SAVE must distinguish accepted bytes from a committed disk file."""
import unittest

from machine import Machine
from ab64.container import loads


class SaveErrorTests(unittest.TestCase):
    def machine(self):
        m = Machine().boot()
        m.command('10 A=7:PRINT A')
        return m

    def assert_recovered(self, m):
        self.assertEqual(m.word(0x70), 0)  # temporary export map released
        self.assertIsNone(m.channel)
        self.assertFalse(m.input_channel or m.output_channel)
        self.assertFalse(m.status_talking)
        self.assertEqual(m.memory.bank, 0)
        self.assertIn('10 A = 7 : PRINT A', m.command('LIST'))
        self.assertEqual(m.command('RUN').split('\r')[0], ' 7 ')

    def test_transport_errors_during_open_write_and_close_are_reported(self):
        for phase in ('open_carry', 'open_status', 'select_carry', 'select_status',
                      'first_byte', 'later_byte', 'close'):
            with self.subTest(phase=phase):
                m = self.machine()
                original_step = m.step
                writes = 0
                injected = False

                def step():
                    nonlocal writes, injected
                    pc = m.cpu.pc
                    writing = m.output_channel
                    result = original_step()
                    if pc == 0xffd2 and writing:
                        writes += 1
                    match = {
                        'open_carry': pc == 0xffc0,
                        'open_status': pc == 0xffc0,
                        'select_carry': pc == 0xffc9,
                        'select_status': pc == 0xffc9,
                        'first_byte': pc == 0xffd2 and writing and writes == 1,
                        'later_byte': pc == 0xffd2 and writing and writes == 20,
                        'close': pc == 0xffc3,
                    }[phase]
                    if match and not injected:
                        injected = True
                        if phase.endswith('_carry'):
                            m.cpu.p |= 1
                        else:
                            m.memory.ram[0x90] = 0x80
                    return result

                m.step = step
                self.assertIn('?DEVICE ERROR', m.command('SAVE "VOID4.AB",8'))
                self.assertTrue(injected)
                self.assert_recovered(m)
                m.step = original_step
                self.assertNotIn('?', m.command('SAVE "RETRY.AB",8'))
                self.assertEqual(sorted(loads(bytes(m.files['RETRY.AB']))[1]), [10])

    def test_dos_errors_after_close_are_reported_even_when_writes_succeed(self):
        for status in (b'26,WRITE PROTECT ON,00,00\r', b'63,FILE EXISTS,00,00\r',
                       b'72,DISK FULL,00,00\r', b'74,DRIVE NOT READY,18,00\r'):
            with self.subTest(status=status):
                m = self.machine()
                m.device_status = status
                self.assertIn('?DEVICE ERROR', m.command('SAVE "VOID4.AB",8'))
                # These errors arrive only through DOS, after a complete stream.
                self.assertEqual(sorted(loads(bytes(m.files['VOID4.AB']))[1]), [10])
                self.assert_recovered(m)

    def test_dos_status_requires_complete_success_response(self):
        for status in (b'', b'0', b'00', b'00,OK', b'00'+b'X'*80+b'\r', b'X0\r'):
            with self.subTest(status=status):
                m = self.machine()
                m.device_status = status
                self.assertIn('?DEVICE ERROR', m.command('SAVE "BADSTATUS",8'))
                self.assert_recovered(m)

    def test_status_bus_failures_are_reported_and_release_the_bus(self):
        for address in (0xffb4, 0xff96, 0xffa5):
            with self.subTest(address=address):
                m = self.machine()
                original_step = m.step
                injected = False

                def step():
                    nonlocal injected
                    pc = m.cpu.pc
                    result = original_step()
                    if pc == address and not injected:
                        injected = True
                        m.memory.ram[0x90] = 0x80
                    return result

                m.step = step
                self.assertIn('?DEVICE ERROR', m.command('SAVE "STATUSFAIL",8'))
                self.assertTrue(injected)
                self.assert_recovered(m)

    def test_successful_save_checks_status_after_closing_data_channel(self):
        m = self.machine()
        start = len(m.services)
        self.assertNotIn('?', m.command('SAVE "GOOD.AB",8'))
        services = m.services[start:]
        close_data = next(i for i, call in enumerate(services)
                          if call[0] == 0xffc3 and call[2] == 1)
        talk_status = next(i for i, call in enumerate(services)
                           if call[0] == 0xffb4 and call[2] == 8)
        self.assertGreater(talk_status, close_data)
        self.assertTrue(any(call[0] == 0xff96 and call[2] == 0x6f for call in services))
        self.assertTrue(any(call[0] == 0xffab for call in services))
        self.assertEqual([call[2] for call in services if call[0] == 0xffc3], [1])
        self.assertEqual(sorted(loads(bytes(m.files['GOOD.AB']))[1]), [10])


if __name__ == '__main__':
    unittest.main()
