"""Banked ABI nesting, interrupt boundaries and shadow-RAM service arguments."""
import unittest
from machine import Machine
from ab64.tokens import word

BANK_SHADOW = 0xbe3


class ServiceTests(unittest.TestCase):
    def descriptor(self, m, bank, mode, target):
        return b'\x20'+word(m.labels['bank_call'])+bytes((bank, mode))+word(target)

    def rom_code(self, m, bank, address, code):
        rom = bytearray(m.memory.rom)
        offset = bank*8192+address-0x8000
        rom[offset:offset+len(code)] = code
        m.memory.rom = bytes(rom)

    def run_to(self, m, stop, limit=10000):
        for _ in range(limit):
            if m.cpu.pc == stop:
                return
            self.assertTrue(m.step())
        self.fail(f'Banked call did not return: ${m.cpu.pc:04X}')

    def test_boot_installs_stubs_after_page_three_clear(self):
        m = Machine()
        m.memory.ram[0x334:0x400] = bytes([0xa5])*204
        m.boot()
        for image in ('SERVICE_GATEWAY', 'COMPILER', 'RUNTIME'):
            bank = {'SERVICE_GATEWAY':0, 'COMPILER':1, 'RUNTIME':2}[image]
            load = m.labels[f'__{image}_LOAD__']
            run = m.labels[f'__{image}_RUN__']
            size = m.labels[f'__{image}_SIZE__']
            offset = bank*8192+load-0x8000
            self.assertEqual(m.memory.ram[run:run+size], m.memory.rom[offset:offset+size])
        self.assertLessEqual(m.labels['__SERVICE_GATEWAY_SIZE__'], 204)
        self.assertTrue(0x334 <= m.labels['read_number'] < 0x400)
        self.assertTrue(0x8000 <= m.labels['rom_read_number'] < 0xa000)
        self.assertEqual(m.memory.ram[0x334+m.labels['__SERVICE_GATEWAY_SIZE__']:0x400],
                         bytes(204-m.labels['__SERVICE_GATEWAY_SIZE__']))

    def test_registers_flags_full_port_bank_and_stack(self):
        m = Machine().boot()
        # Capture the incoming registers/P, then return specified registers/flags.
        self.rom_code(m, 4, 0x9d00, bytes.fromhex(
            '8d41078e42078c430708688d4007a965a27ea0ad38b860'))
        for mode,caller in ((mode,caller) for mode in (0xb4,0xb5,0xb7) for caller in (0x700,0xc0fb)):
            for interrupt_mask in (0, 4):
                with self.subTest(mode=mode, caller=caller, interrupt_mask=interrupt_mask):
                    ram = m.memory.ram
                    m.memory[0xde00] = 6
                    ram[BANK_SHADOW] = 6
                    ram[1] = mode
                    ram[caller:caller+7] = self.descriptor(m, 4, 7, 0x9d00)
                    c = m.cpu
                    c.pc=caller; c.sp=0xe0; c.a=0x11; c.x=0x22; c.y=0x33; c.p=0x69|interrupt_mask
                    for _ in range(200):
                        m.step()
                        if 0x8000<=c.pc<0xa000:break
                    self.assertEqual(c.pc,0x9d00, 'The first ROM instruction must be the requested target')
                    self.run_to(m, caller+7)
                    self.assertEqual(ram[0x741:0x744], bytes.fromhex('112233'))
                    self.assertEqual(ram[0x740]&0xcd, (0x69|interrupt_mask)&0xc5)
                    self.assertEqual((c.a,c.x,c.y,c.sp), (0x65,0x7e,0xad,0xe0))
                    self.assertEqual(c.p&0xcf, 0x81|interrupt_mask)
                    self.assertEqual((ram[1],ram[BANK_SHADOW],m.memory.bank), (mode,6,6))

    def nested_machine(self):
        m = Machine().boot()
        ram=m.memory.ram
        # RAM -> ROM bank 4 -> ROM bank 6 -> RAM -> KERNAL bank 0.
        self.rom_code(m, 4, 0x9d00, self.descriptor(m,6,7,0x9d00)+bytes.fromhex('ad e3 0b 8d 47 07 a9 33 38 60'))
        self.rom_code(m, 6, 0x9d00, self.descriptor(m,0xff,5,0x760)+bytes.fromhex('ad e3 0b 8d 49 07 60'))
        callback = bytes.fromhex('ad23a18d4807')+b'\x20'+word(m.labels['kernal_gate'])+bytes.fromhex('8d44078e45078c460760')
        ram[0x760:0x760+len(callback)] = callback
        ram[0xa123] = 0x5a
        ram[m.labels['service_call']+1:m.labels['service_call']+3] = word(0xffde)
        ram[0x700:0x707] = self.descriptor(m,4,7,0x9d00)
        m.memory[0xde00]=3;ram[BANK_SHADOW]=3;ram[1]=0xb5
        c=m.cpu;c.pc=0x700;c.sp=0xe0;c.a=1;c.x=2;c.y=3;c.p=0x21
        return m

    def assert_nested_result(self, m):
        ram=m.memory.ram;c=m.cpu
        self.assertEqual((c.pc,c.sp,c.a,c.p&1), (0x707,0xe0,0x33,1))
        self.assertEqual((ram[1],ram[BANK_SHADOW],m.memory.bank), (0xb5,3,3))
        self.assertEqual(ram[0x744:0x747], bytes.fromhex('341200'))
        self.assertEqual((ram[0x747],ram[0x748],ram[0x749]), (4,0x5a,6))

    def test_nested_rom_ram_and_kernal_calls(self):
        m=self.nested_machine()
        self.run_to(m,0x707)
        self.assert_nested_result(m)

    def test_blocking_input_keeps_irqs_enabled_and_resumes_bank_frames(self):
        m=Machine().boot()
        self.assertEqual(m.command('INPUT A$'), '? ')
        self.assertEqual(m.cpu.pc, 0xffcf)
        self.assertFalse(m.cpu.p&4)
        # Waiting inside the nested KERNAL call temporarily owns bank 0.
        self.assertEqual((m.memory.bank,m.memory.ram[BANK_SHADOW]), (0,0))
        waiting_sp=m.cpu.sp
        for interrupt in ('irq','nmi'):
            getattr(m.cpu,interrupt)()
            self.run_to(m,0xffcf)
            self.assertEqual(m.cpu.sp,waiting_sp)
        m.input.extend(b'HELLO\r')
        m.pump()
        self.assertEqual((m.memory.bank,m.memory.ram[BANK_SHADOW],m.memory.ram[1]&7), (0,0,7))
        self.assertEqual(m.command('PRINT A$').split('\r')[0], 'HELLO')

    def test_interrupts_at_nested_transition_boundaries(self):
        baseline=self.nested_machine()
        ram_image=bytes(baseline.memory.ram);rom_image=baseline.memory.rom
        boundaries=[];step=0
        while baseline.cpu.pc!=0x707:
            pc=baseline.cpu.pc;op=baseline.memory[pc]
            if (op==0x85 and baseline.memory[pc+1]==1 or
                op==0x8d and baseline.memory[pc+1]|baseline.memory[pc+2]<<8 in (0xde00,BANK_SHADOW) or
                op==0x28 or pc in (0x9d00,0x760)):
                boundaries.append(step)
            baseline.step();step+=1
        self.assert_nested_result(baseline)
        for interrupt in ('irq','nmi'):
            for boundary in boundaries:
                with self.subTest(interrupt=interrupt, boundary=boundary):
                    m=Machine();m.memory.ram[:]=ram_image;m.memory.rom=rom_image
                    m.memory.bank=3
                    c=m.cpu;c.pc=0x700;c.sp=0xe0;c.a=1;c.x=2;c.y=3;c.p=0x21
                    for _ in range(boundary):m.step()
                    pending=True
                    for _ in range(2000):
                        if pending and (interrupt=='nmi' or not c.p&4):
                            getattr(c,interrupt)();pending=False
                        if c.pc==0x707:break
                        m.step()
                    self.assertFalse(pending)
                    self.assert_nested_result(m)

    def test_definition_activation_reads_inline_operands_under_rom(self):
        for address in (0x8100,0xa100,0xe100):
            with self.subTest(address=address):
                m=Machine().boot()
                m.command('10 DEF FN DOUBLE(X)=X*2')
                m.command('20 PRINT FN DOUBLE(123):END')
                anchor=m.state('head');payload=m.word(anchor+5);size=m.word(payload-2)
                m.command('10')
                # Recompile the body at a chosen shadow address with existing bindings.
                old_free=m.state('free')
                m.memory.ram[0xb00:0xb02]=word(address)
                m.memory.ram[address:address+4]=word(size)+word(old_free)
                self.assertNotIn('?',m.command('10 DEF FN DOUBLE(X)=X*2'))
                self.assertEqual(m.word(anchor+5),address+2)
                self.assertEqual(m.command('RUN').split('\r')[0],' 246 ')

    def test_data_spelling_in_shadow_ram_and_service_errors(self):
        m=Machine().boot()
        m.command('5 RESERVE $A200,$100')
        m.command('10 DATA 001,$D000,"TEXT",-$000D')
        m.command('20 READ A$,B,C$,D:PRINT A$;B;C$;D:RESTORE:READ E:PRINT E')
        anchor=m.state('head')
        # The next anchor is the DATA line; copy its complete physical payload.
        payload=m.word(anchor+5);size=m.word(payload-2)
        anchor=m.word(payload-2+size-2)
        payload=m.word(anchor+5);size=m.word(payload-2)
        self.assertLess(size,256)
        m.memory.ram[0xa200:0xa200+size]=m.memory.ram[payload-2:payload-2+size]
        m.memory.ram[anchor+5:anchor+7]=word(0xa202)
        m.memory.ram[anchor+1:anchor+3]=word(0xa203+m.memory.ram[0xa202])
        self.assertEqual(m.command('RUN').split('\r')[:2],['001-12288 TEXT-13 ', ' 1 '])
        self.assertIn('?OUT OF DATA',m.command('READ A$:READ A$:READ A$:READ A$'))
        self.assertIn('?UNSUPPORTED FEATURE',m.command('OPEN 2,1'))
        self.assertIn('?ILLEGAL QUANTITY',m.command('GET A\rX'))
        self.assertEqual((m.memory.ram[1]&7,m.memory.bank), (7,0))
        self.assertEqual(m.command('PRINT 7').split('\r')[0], ' 7 ')


if __name__=='__main__':unittest.main()
