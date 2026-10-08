"""Bounded source containers with CRC-16/CCITT-FALSE and dense name export."""
import binascii
from .tokens import Names, SourceError, decode, remap, word, NAME16
MAGIC = b'AB64SRC\0'
MAX_FILE = 65535*256 + 64000*258 + 16


def dumps(names, lines):
    used = set()
    for n, s in sorted(lines.items()):
        if not 0 <= n <= 63999:
            raise SourceError('invalid line number')
        for t in decode(s, names):
            if t.code >= 128 or t.code == NAME16:
                used.add(t.value)
    old = sorted(used)
    mapping = {i:j for j,i in enumerate(old)}
    out = bytearray(MAGIC + b'\x01\0' + word(len(old)))
    for i in old:
        s = names[i].encode('ascii')
        out += bytes((len(s),)) + s
    for n, s in sorted(lines.items()):
        s = remap(s, names, mapping)
        out += word(n) + bytes((len(s),)) + s
    out += b'\xff\xff'
    out += word(binascii.crc_hqx(out, 65535))
    return bytes(out)


def loads(data):
    if len(data) < 16 or len(data) > MAX_FILE:
        raise SourceError('invalid file size')
    if data[:10] != MAGIC + b'\x01\0':
        raise SourceError('invalid source magic/version/flags')
    if binascii.crc_hqx(data[:-2], 65535) != int.from_bytes(data[-2:], 'little'):
        raise SourceError('CRC mismatch')
    p = 12
    count = int.from_bytes(data[10:12], 'little')
    names = Names()
    for _ in range(count):
        if p >= len(data)-4:
            raise SourceError('truncated dictionary')
        n = data[p]
        p += 1
        if not n or p+n > len(data)-4:
            raise SourceError('truncated/empty name')
        try:
            s = data[p:p+n].decode('ascii')
        except UnicodeError as e:
            raise SourceError('invalid name bytes') from e
        if s != s.upper():
            raise SourceError('noncanonical name')
        names.add(s, unique=True)
        p += n
    lines, previous = {}, -1
    while True:
        if p+2 > len(data)-2:
            raise SourceError('missing end marker')
        n = int.from_bytes(data[p:p+2], 'little')
        p += 2
        if n == 65535:
            break
        if not previous < n <= 63999 or p >= len(data)-2:
            raise SourceError('unsorted/invalid line record')
        size = data[p]
        p += 1
        if p+size > len(data)-4:
            raise SourceError('truncated line')
        s = data[p:p+size]
        decode(s, names)
        lines[n] = s
        previous = n
        p += size
    if p != len(data)-2:
        raise SourceError('trailing bytes')
    return names, lines
