"""Instruction-level C64 cartridge harness; KERNAL services are deterministic stubs.

This models PLA visibility/write-through, not VIC cycles, IEC or real IRQ timing.
"""
from pathlib import Path
import re
from py65.devices.mpu6502 import MPU
ROOT = Path(__file__).resolve().parents[2]

class Memory:
    def __init__(self):
        self.ram = bytearray(65536)
        self.rom = (ROOT/'build/assembly-basic.bin').read_bytes()
        self.ram[0], self.ram[1] = 0x2f, 0x37
        self.kernal = bytearray([0xea]*8192)
        # Stock NMI entry shape: SEI; JMP ($0318), before register saves.
        self.kernal[0x1e43:0x1e47]=bytes.fromhex('786c1803')
        self.kernal[0x1ffa:0x1ffc]=bytes.fromhex('43fe')
    def __getitem__(self, i):
        if isinstance(i,slice):
            return [self[j] for j in range(i.start or 0,i.stop or 65536,i.step or 1)]
        mode = self.ram[1] & 7
        if mode == 7 and 0x8000 <= i < 0xc000:
            return self.rom[i-0x8000]
        if mode & 2 and i >= 0xe000:
            return self.kernal[i-0xe000]
        return self.ram[i]
    def __setitem__(self,i,v):
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
        self.input_channel = False
        self.output_channel = False
    def rts(self):
        self.cpu.pc = (self.cpu.stPopWord()+1)&65535
    def step(self):
        c, m = self.cpu, self.memory.ram
        if c.pc == self.labels['report_error']:
            self.errors.append(c.a)
        if c.pc == 0xea31 and m[1]&2:
            c.y=c.stPop();c.x=c.stPop();c.a=c.stPop()
            c.inst_0x40() # stock IRQ completion shape: restore regs and RTI
        elif (c.pc >= 0xff00 or c.pc == 0xfd15) and m[1]&2:
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
                c.p &= ~1
            elif c.pc == 0xffc6:
                m[0x90]=0
                self.input_channel=True
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
            elif c.pc == 0xffd2:
                if self.output_channel:
                    self.files[self.channel].append(c.a)
                    self.rts()
                    self.steps+=1
                    return True
                self.output.append(c.a)
                if c.a == 13:
                    m[0xd3] = 0
                elif c.a >= 32:
                    m[0xd3] = (m[0xd3]+1)%40
            elif c.pc == 0xffe4:
                c.a=self.input.pop(0) if self.input else 0
                c.p=(c.p & ~2) | (2 if c.a==0 else 0)
            elif c.pc == 0xffcf:
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
            self.rts()
        elif c.pc in (0xfda3,0xfd50) and m[1]&2:
            self.services.append((c.pc,m[1]&7,c.a,c.x,c.y))
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
    def command(self,s):
        self.input.extend(s.encode('latin-1')+b'\r')
        start = len(self.output)
        self.pump()
        return bytes(self.output[start:]).decode('latin-1')
    def word(self,p):
        return self.memory.ram[p] | self.memory.ram[p+1]<<8
    def state(self,n):
        # Constants are in assembler listing, intentionally fixed public test ABI.
        offsets = {'head':8,'name_head':2,'slab':6,'line':10,'generation':17,'cont':19,'error':25,'free':0}
        return self.word(0xb00+offsets[n])
