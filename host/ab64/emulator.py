"""Instruction-level C64 cartridge harness; KERNAL services are deterministic stubs.

This models classic Magic Desk banks and PLA visibility/write-through, not VIC
cycles, IEC or real IRQ timing.
"""
from pathlib import Path
import re
from py65.devices.mpu6502 import MPU
ROOT = Path(__file__).resolve().parents[2]

class Memory:
    def __init__(self):
        self.ram = bytearray(65536)
        self.rom = (ROOT/'build/assembly-basic.bin').read_bytes()
        if len(self.rom) != 65536:
            raise ValueError('Expected a 64-KiB classic Magic Desk ROM')
        self.bank = 0
        self.cart_enabled = True
        self.bank_writes = []
        self.ram[0], self.ram[1] = 0x2f, 0x37
        self.basic = bytearray([0xea]*8192)
        self.character = bytearray([0xea]*4096)
        self.kernal = bytearray([0xea]*8192)
        # Stock NMI entry shape: SEI; JMP ($0318), before register saves.
        self.kernal[0x1e43:0x1e47]=bytes.fromhex('786c1803')
        self.kernal[0x1ffa:0x1ffc]=bytes.fromhex('43fe')
        # Stock IRQ entry saves A/X/Y before dispatching through $0314.
        self.kernal[0x1f48:0x1f50]=bytes.fromhex('488a4898486c1403')
        self.kernal[0x1ffe:0x2000]=bytes.fromhex('48ff')
    def port_bits(self):
        # LORAM/HIRAM/CHAREN inputs are pulled high. The data latch alone
        # does not determine the map until the corresponding DDR bits are set.
        return ((self.ram[1] & self.ram[0]) | (~self.ram[0] & 7)) & 7
    def __getitem__(self, i):
        if isinstance(i,slice):
            return [self[j] for j in range(i.start or 0,i.stop or 65536,i.step or 1)]
        if i == 1:
            return (self.ram[1] & 0xf8) | self.port_bits()
        mode = self.port_bits()
        if mode & 3 == 3:
            if self.cart_enabled and 0x8000 <= i < 0xa000:
                return self.rom[self.bank*8192+i-0x8000]
            if 0xa000 <= i < 0xc000:
                return self.basic[i-0xa000]
        if mode & 3 and 0xd000 <= i < 0xe000:
            if not mode & 4:
                return self.character[i-0xd000]
            if 0xde00 <= i <= 0xdeff:
                return 0xff  # Write-only IO1 bank latch; open bus is not modelled.
        if mode & 2 and i >= 0xe000:
            return self.kernal[i-0xe000]
        return self.ram[i]
    def __setitem__(self,i,v):
        mode = self.port_bits()
        if mode & 4 and mode & 3 and 0xde00 <= i <= 0xdeff:
            self.bank = v & 7
            self.cart_enabled = not bool(v & 128)
            self.bank_writes.append(v & 255)
        else:
            self.ram[i] = v & 255

class Machine:
    def __init__(self):
        self.memory = Memory()
        self.cpu = MPU(memory=self.memory,pc=int.from_bytes(self.memory.rom[:2],'little'))
        self.labels = {}
        for s in (ROOT/'build/assembly-basic.lbl').read_text().splitlines():
            m = re.match(r'al (\w+) \.(.+)',s)
            if m:
                self.labels[m[2]] = int(m[1],16)
        self.output = bytearray()
        self.input = bytearray()
        self.steps = 0
        self.jiffy=0x1234
        self.services = []
        self.errors = []
        self.files = {}
        self.filename = ''
        self.channel = None
        self.file_cursor = 0
        self.file_write = False
        self.device_status = b'00, OK,00,00\r'
        self.status_talking = False
        self.input_channel = False
        self.output_channel = False
    def rts(self):
        self.cpu.pc = (self.cpu.stPopWord()+1)&65535
    def step(self):
        c, m = self.cpu, self.memory.ram
        if (c.pc in (self.labels.get('editor_wait'), self.labels.get('editor_input_wait')) and self.memory.bank == 3
                and m[0x3cc] and not self.input and not m[0x77]):
            return False
        if (c.pc in tuple(self.labels.get(n) for n in ('be_wait','be_prompt_wait','be_modal_key','be_color_wait'))
                and self.memory.bank == 4 and m[0x2f7] and not self.input):
            return False
        if c.pc == self.labels['report_error']:
            self.errors.append(c.a)
        if c.pc == 0xea31 and m[1]&2:
            c.y=c.stPop();c.x=c.stPop();c.a=c.stPop()
            c.inst_0x40() # stock IRQ completion shape: restore regs and RTI
        elif (c.pc >= 0xff00 and not 0xff48 <= c.pc < 0xff50 or c.pc == 0xfd15) and m[1]&2:
            self.services.append((c.pc,m[1]&7,c.a,c.x,c.y))
            if c.pc == 0xffbd:
                p=c.x | c.y<<8
                self.filename=bytes(m[p:p+c.a]).decode('latin-1')
            elif c.pc == 0xffba:
                pass
            elif c.pc == 0xffc0:
                m[0x90]=0
                self.channel=self.filename.split(',')[0]
                self.file_write=self.filename.endswith(',W')
                self.file_cursor=0
                if self.file_write:
                    self.files[self.channel]=bytearray()
                if self.filename.endswith(',S,R') and self.channel not in self.files:
                    c.p |= 1
                else:
                    c.p &= ~1
            elif c.pc == 0xffc6:
                m[0x90]=0
                self.input_channel=True
                if self.channel in self.files and not self.files[self.channel]:
                    m[0x90]=64
                c.p &= ~1
            elif c.pc == 0xffc9:
                self.output_channel=True
                self.file_write=True
                self.files[self.channel]=bytearray()
                c.p &= ~1
            elif c.pc == 0xffcc:
                self.input_channel=False
                self.output_channel=False
            elif c.pc == 0xffc3:
                self.channel=None
            elif c.pc == 0xffb4:
                self.file_cursor=0
            elif c.pc == 0xff96:
                self.status_talking=c.a == 0x6f
            elif c.pc == 0xffa5 and self.status_talking:
                if self.file_cursor >= len(self.device_status):
                    c.a=0
                    m[0x90]=2  # no status response: serial read timeout
                else:
                    c.a=self.device_status[self.file_cursor]
                    self.file_cursor+=1
                    m[0x90]=64 if self.file_cursor==len(self.device_status) else 0
                c.p=(c.p & ~0x83) | (c.a & 0x80) | (2 if c.a==0 else 0)
            elif c.pc == 0xffab:
                self.status_talking=False
            elif c.pc == 0xffd2:
                if self.output_channel:
                    self.files[self.channel].append(c.a)
                    c.p &= ~1
                    self.rts()
                    self.steps+=1
                    return True
                self.output.append(c.a)
                vector=m[0x326] | m[0x327]<<8
                if vector == self.labels.get('editor_output_gate'):
                    c.pc=vector
                    self.steps+=1
                    return True
                if c.a == 13:
                    m[0xd3] = 0
                    m[0xd6] = min(m[0xd6]+1,24)
                elif c.a >= 32:
                    m[0xd3] = (m[0xd3]+1)%40
            elif c.pc == 0xffe4:
                c.a=self.input.pop(0) if self.input else 0
                c.p=(c.p & ~2) | (2 if c.a==0 else 0)
            elif c.pc == 0xffcf:
                vector=m[0x324] | m[0x325]<<8
                if not self.input_channel and vector == self.labels.get('editor_input_gate'):
                    c.pc=vector
                    self.steps+=1
                    return True
                if self.input_channel:
                    data=self.files.get(self.channel,b'')
                    if self.file_cursor >= len(data):
                        raise AssertionError('firmware read beyond file EOF')
                    c.a=data[self.file_cursor]
                    self.file_cursor+=1
                    m[0x90]=64 if self.file_cursor==len(data) else 0
                else:
                    if not self.input:
                        return False
                    c.a = self.input.pop(0)
                c.p = (c.p & ~2) | (2 if c.a == 0 else 0)
            elif c.pc == 0xffe1:
                c.a = 255
                c.p &= ~2
            elif c.pc == 0xffde:
                c.a,c.x,c.y = self.jiffy&255,(self.jiffy>>8)&255,(self.jiffy>>16)&255
            elif c.pc == 0xffdb:
                self.jiffy=c.a | c.x<<8 | c.y<<16
            elif c.pc == 0xfd15:
                m[0x314],m[0x315] = 0x31,0xea
                m[0x326],m[0x327] = 0xca,0xf1
                m[0x324],m[0x325] = 0x57,0xf1
                m[0x9a]=3
            self.rts()
        elif c.pc in (0xfda3,0xfd50) and m[1]&2:
            self.services.append((c.pc,m[1]&7,c.a,c.x,c.y))
            if c.pc == 0xfd50:
                m[0x200:0x400] = bytes(512) # RAMTAS clears system/user buffers.
            self.rts()
        else:
            c.step()
        self.steps += 1
        return True
    def pump(self, limit=2000000):
        for _ in range(limit):
            if not self.step():
                return
        raise AssertionError(f'CPU did not reach input: pc=${self.cpu.pc:04X}, stack=${self.cpu.sp:02X}, map={self.memory.ram[1]&7}')
    def boot(self):
        self.pump()
        return self
    def command(self,s,include_input_newline=False):
        self.input.extend(s.encode('latin-1')+b'\r')
        start = len(self.output)
        self.pump()
        result=bytes(self.output[start:]).decode('latin-1')
        # A console caller already echoes Enter. Keep its CR in output history,
        # but return only command output unless the screen trace is requested.
        if not include_input_newline and result.startswith('\r'):
            result=result[1:]
        return result
    def word(self,p):
        return self.memory.ram[p] | self.memory.ram[p+1]<<8
    def state(self,n):
        # Constants are in assembler listing, intentionally fixed public test ABI.
        offsets = {'head':8,'name_head':2,'slab':6,'line':10,'generation':17,'cont':19,'error':25,'free':0}
        return self.word(0xb00+offsets[n])
