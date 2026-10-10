"""Magic Desk latch, image copies and common-RAM transition regressions."""
import unittest
from machine import Machine, Memory
from ab64.tokens import word

BANK_SHADOW=0xbe3

class BankingTests(unittest.TestCase):
    def invoke(self,m,label,limit=10000):
        c=m.cpu;c.pc=m.labels[label];c.sp=0xfd;c.stPushWord(0x6ff)
        for _ in range(limit):
            m.step()
            if c.pc==0x700:return
        self.fail(f'{label} did not return: ${c.pc:04x}')

    def test_latch_and_pla_visibility(self):
        mem=Memory()
        for bank in range(8):
            mem[0xde00]=bank
            self.assertEqual(bytes(mem[0x8000:0xa000]),mem.rom[bank*8192:(bank+1)*8192])
            self.assertEqual(mem[0xa000],0xea) # BASIC ROM, not a second cartridge window
            mem[0x8100]=0x55
            self.assertEqual(mem.ram[0x8100],0x55)
        mem[0xde7f]=2
        self.assertEqual(mem.bank,2)
        mem.ram[1]=0x35
        self.assertEqual(mem[0x8100],0x55)
        mem.ram[1]=0x34
        mem[0xde00]=5
        self.assertEqual(mem.bank,2) # I/O hidden: write reaches RAM
        mem.ram[1]=0x37;mem[0xde00]=0x80
        self.assertEqual(mem[0x8100],0x55)
        mem[0xde00]=1
        self.assertTrue(mem.cart_enabled)
        self.assertEqual(mem.bank,1)

    def test_boot_copies_exact_images(self):
        m=Machine().boot();ram=m.memory.ram
        for image in ('COMPILER','RUNTIME'):
            start=m.labels[f'__{image}_RUN__'];size=m.labels[f'__{image}_SIZE__']
            bank=1 if image=='COMPILER' else 2
            self.assertEqual(ram[start:start+size],m.memory.rom[bank*8192+9:bank*8192+9+size])
        self.assertEqual(m.memory.bank_writes[:5],[0,2,0,1,0])
        self.assertEqual((m.memory.bank,ram[BANK_SHADOW],ram[1]),(0,0,0x37))

    def test_copy_preserves_bank_full_port_and_flags(self):
        for mapping in (0x35,0x34):
            m=Machine().boot();c=m.cpu;ram=m.memory.ram
            m.memory[0xde00]=3;ram[BANK_SHADOW]=3;ram[1]=mapping
            ram[0x12:0x14]=word(0x8009);ram[0x10:0x12]=word(0x600);ram[0xe:0x10]=word(64)
            c.a=1;c.p=0x21
            self.invoke(m,'copy_bank_image')
            self.assertEqual(ram[0x600:0x640],m.memory.rom[8192+9:8192+73])
            self.assertEqual((m.memory.bank,ram[BANK_SHADOW],ram[1],c.sp,c.p&0xcf),(3,3,mapping,0xfd,1))

    def test_irq_restores_nonzero_bank(self):
        m=Machine().boot();c=m.cpu;ram=m.memory.ram
        m.memory[0xde00]=6;ram[BANK_SHADOW]=6;ram[1]=0x34
        c.pc=0x700;c.sp=0xfd;c.a=0x11;c.x=0x22;c.y=0x33;c.p=0x21;c.irq()
        for _ in range(250):
            m.step()
            if c.pc==0x700:break
        self.assertEqual((c.pc,c.sp,c.a,c.x,c.y),(0x700,0xfd,0x11,0x22,0x33))
        self.assertEqual((m.memory.bank,ram[BANK_SHADOW],ram[1]),(6,6,0x34))
        self.assertEqual(m.memory.bank_writes[-2:],[0,6])

    def test_kernal_gate_restores_nonzero_bank(self):
        m=Machine().boot();c=m.cpu;ram=m.memory.ram
        ram[m.labels['service_call']+1:m.labels['service_call']+3]=word(0xffde)
        m.memory[0xde00]=4;ram[BANK_SHADOW]=4;ram[1]=0x34;c.p=0x25
        self.invoke(m,'kernal_gate')
        self.assertEqual((c.a,c.x,c.y),(0x34,0x12,0))
        self.assertEqual((m.memory.bank,ram[BANK_SHADOW],ram[1]),(4,4,0x34))
        self.assertTrue(c.p&4)

    def test_nmi_during_image_copy(self):
        m=Machine().boot();c=m.cpu;ram=m.memory.ram
        ram[0x12:0x14]=word(0x8009);ram[0x10:0x12]=word(0x600);ram[0xe:0x10]=word(64)
        c.pc=m.labels['copy_bank_image'];c.sp=0xfd;c.stPushWord(0x6ff);c.a=1;c.p=0x21
        injected=False
        for _ in range(10000):
            if m.memory.bank==1 and not injected:
                injected=True;c.nmi()
            m.step()
            if c.pc==0x700:break
        self.assertTrue(injected)
        self.assertEqual(c.pc,0x700)
        self.assertEqual(ram[0x600:0x640],m.memory.rom[8192+9:8192+73])
        self.assertEqual((m.memory.bank,ram[BANK_SHADOW],ram[1],c.sp),(0,0,0x37,0xfd))

    def test_sys_usr_restore_bank_after_user_mapping_change(self):
        for mapping in (0x37,0x34):
            m=Machine().boot();ram=m.memory.ram
            # Switch bank, hide/expose I/O, return $1234 in A/X.
            code=bytes.fromhex('a9078d00de')+bytes((0xa9,mapping))+bytes.fromhex('8501a934a21260')
            ram[0x700:0x700+len(code)]=code
            self.assertNotIn('?',m.command('SYS $0700:POKE $D021,1'))
            self.assertEqual(ram[0xd021],1)
            ram[0x311:0x313]=word(0x700)
            self.assertEqual(m.command('PRINT USR(1)').split('\r')[0],' 4660 ')
            self.assertEqual((m.memory.bank,ram[BANK_SHADOW]),(0,0))

    def test_warm_header_recovers_from_auxiliary_bank(self):
        m=Machine().boot();m.command('10 PRINT 9')
        for bank in range(1,8):
            m.memory[0xde00]=bank;m.memory.ram[BANK_SHADOW]=bank
            m.cpu.pc=int.from_bytes(m.memory.rom[bank*8192+2:bank*8192+4],'little')
            m.pump()
            self.assertEqual((m.memory.bank,m.memory.ram[BANK_SHADOW]),(0,0))
            self.assertIn('10 PRINT 9',m.command('LIST'))
