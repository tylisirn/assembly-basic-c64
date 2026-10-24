"""Bounded source containers with CRC-16/CCITT-FALSE and dense name export."""
import binascii
from dataclasses import dataclass
from .tokens import Names, SourceError, decode, remap, word, NAME16
MAGIC = b'AB64SRC\0'
MAX_FILE = 65535*256 + 64000*258 + 16


@dataclass(frozen=True)
class Reservation:
    start: int
    size: int
    basic: bool = False

@dataclass(frozen=True)
class Blob:
    reservation: int
    start: int
    data: bytes
    kind: str = 'BIN'
    multicolor: bool = False
    colors: tuple = (0, 7, 1, 9)

class ProgramLines(dict):
    """Line mapping that retains optional binary metadata through source tools."""
    def __init__(self, *args, reservations=(), blobs=(), **kwargs):
        super().__init__(*args, **kwargs)
        self.reservations = tuple(reservations)
        self.blobs = tuple(blobs)


def validate_metadata(reservations, blobs):
    if len(reservations) > 8 or len(blobs) > 16:
        raise SourceError('binary metadata capacity exceeded')
    ranges = []
    for r in reservations:
        end = r.start + r.size
        if (not r.size or not ((0x2c00 <= r.start < end <= 0xd000) or
                              (0xe000 <= r.start < end <= 0xe400)) or
                r.basic not in (False, True) or
                (r.basic and (r.start % 256 or r.size % 256))):
            raise SourceError('invalid binary reservation')
        if any(r.start < hi and end > lo for lo, hi in ranges):
            raise SourceError('overlapping binary reservations')
        ranges.append((r.start, end))
    occupied = []
    for b in blobs:
        if (b.kind not in ('BIN', 'SPR', 'ASM') or not 0 <= b.reservation < len(ranges)
                or not 1 <= len(b.data) <= 65535 or len(b.colors) != 4
                or any(not isinstance(c, int) or not 0 <= c <= 15 for c in b.colors)
                or b.multicolor not in (False, True)
                or (b.kind != 'SPR' and b.multicolor)
                or (b.kind == 'SPR' and len(b.data) != 64)):
            raise SourceError('invalid binary blob')
        lo, hi = ranges[b.reservation]
        end = b.start + len(b.data)
        if not lo <= b.start < end <= hi or any(b.start < h and end > l for l, h in occupied):
            raise SourceError('blob outside reservation or overlaps another blob')
        occupied.append((b.start, end))


def dumps(names, lines, *, reservations=None, blobs=None):
    reservations = tuple(getattr(lines, "reservations", ()) if reservations is None else reservations)
    blobs = tuple(getattr(lines, "blobs", ()) if blobs is None else blobs)
    validate_metadata(reservations, blobs)
    version = 2 if reservations or blobs else 1
    used = set()
    for n, s in sorted(lines.items()):
        if not 0 <= n <= 63999:
            raise SourceError('invalid line number')
        for t in decode(s, names):
            if t.code >= 128 or t.code == NAME16:
                used.add(t.value)
    old = sorted(used)
    mapping = {i:j for j,i in enumerate(old)}
    out = bytearray(MAGIC + bytes((version, 0)))
    if version == 2:
        out.append(len(reservations))
        for r in reservations:
            out += word(r.start) + word(r.size) + bytes((int(r.basic),))
    out += word(len(old))
    for i in old:
        s = names[i].encode('ascii')
        out += bytes((len(s),)) + s
    for n, s in sorted(lines.items()):
        s = remap(s, names, mapping)
        out += word(n) + bytes((len(s),)) + s
    out += b'\xff\xff'
    if version == 2:
        out.append(len(blobs))
        for b in blobs:
            bg, sp, c1, c2 = b.colors
            flags = ('BIN', 'SPR', 'ASM').index(b.kind) | (0x80 if b.multicolor else 0)
            out += bytes((b.reservation,)) + word(b.start) + word(len(b.data))
            out += bytes((flags, bg | sp << 4, c1 | c2 << 4)) + bytes(b.data)
    out += word(binascii.crc_hqx(out, 65535))
    return bytes(out)


def loads(data):
    if len(data) < 16 or len(data) > MAX_FILE:
        raise SourceError('invalid file size')
    if data[:8] != MAGIC or data[8] not in (1, 2) or data[9] != 0:
        raise SourceError('invalid source magic/version/flags')
    if binascii.crc_hqx(data[:-2], 65535) != int.from_bytes(data[-2:], 'little'):
        raise SourceError('CRC mismatch')
    p = 10
    def take(n):
        nonlocal p
        if p+n > len(data)-2:
            raise SourceError('truncated binary metadata/data')
        result = data[p:p+n]
        p += n
        return result
    reservations = []
    if data[8] == 2:
        count = take(1)[0]
        if count > 8:
            raise SourceError('binary reservation capacity exceeded')
        for _ in range(count):
            record = take(5)
            if record[4] not in (0, 1):
                raise SourceError('invalid reservation flags')
            reservations.append(Reservation(int.from_bytes(record[:2], 'little'),
                                            int.from_bytes(record[2:4], 'little'), bool(record[4])))
        validate_metadata(reservations, [])
    count = int.from_bytes(take(2), 'little')
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
    lines, previous = ProgramLines(), -1
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
    if data[8] == 2:
        count = take(1)[0]
        if count > 16:
            raise SourceError('binary blob capacity exceeded')
        blobs = []
        for _ in range(count):
            r = take(8)
            if r[5] & 0x7f > 2:
                raise SourceError('invalid binary blob type')
            size = int.from_bytes(r[3:5], 'little')
            blobs.append(Blob(r[0], int.from_bytes(r[1:3], 'little'), bytes(take(size)),
                              ('BIN','SPR','ASM')[r[5] & 0x7f], bool(r[5] & 0x80),
                              (r[6] & 15, r[6] >> 4, r[7] & 15, r[7] >> 4)))
        validate_metadata(reservations, blobs)
        lines.reservations, lines.blobs = tuple(reservations), tuple(blobs)
    if p != len(data)-2:
        raise SourceError('trailing bytes')
    return names, lines
