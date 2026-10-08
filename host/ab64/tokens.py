"""Normative Appendix A v1 codec. Payloads are bytes, never recursive tokens."""
from dataclasses import dataclass
import re

PUNCT = (':', ',', ';', '(', ')', '+', '-', '*', '/', '^', '=', '<', '>', '<=', '>=', '<>')
KEYWORDS = ('END FOR NEXT DATA INPUT# INPUT DIM READ LET GOTO RUN IF RESTORE GOSUB RETURN REM STOP ON WAIT LOAD SAVE VERIFY DEF POKE PRINT# PRINT CONT LIST CLR CMD SYS OPEN CLOSE GET GET# NEW TAB( TO FN SPC( THEN NOT STEP AND OR SGN INT ABS USR FRE POS SQR RND LOG EXP COS SIN TAN ATN PEEK LEN STR$ VAL ASC CHR$ LEFT$ RIGHT$ MID$ ST TI TI$ π').split()
CODES = {s: i for i, s in enumerate(PUNCT)} | {s: 0x20+i for i, s in enumerate(KEYWORDS)}
SPELLINGS = {v: k for k, v in CODES.items()}
DEC8, DEC16, HEX16, STRING, REMTEXT, DATA_TEXT, DATA_SPELLING, NUMTEXT, BADTEXT, NAME16 = range(0x10, 0x1a)
RAW = {STRING, REMTEXT, DATA_TEXT, DATA_SPELLING, NUMTEXT, BADTEXT}
NAME_RE = re.compile(r'[A-Z][A-Z0-9]*[%$]?\Z')
NUM_RE = re.compile(r'([+-]?)(\$[0-9A-Fa-f]{1,4}|[0-9]+)\Z')

class SourceError(ValueError):
    pass

class Names:
    def __init__(self, names=()):
        self.names = []
        self.ids = {}
        for n in names:
            self.add(n, unique=True)

    def add(self, name, unique=False):
        name = name.upper()
        if not NAME_RE.fullmatch(name) or name in CODES or len(name) > 255:
            raise SourceError('invalid dictionary name')
        if name in self.ids:
            if unique:
                raise SourceError('duplicate dictionary name')
            return self.ids[name]
        if len(self.names) >= 65535:
            raise SourceError('name dictionary full')
        i = len(self.names)
        self.names.append(name)
        self.ids[name] = i
        return i

    def copy(self):
        return Names(self.names)

    def __getitem__(self, index):
        try:
            return self.names[index]
        except IndexError as e:
            raise SourceError('invalid name ID') from e


def word(n):
    if not 0 <= n <= 65535:
        raise SourceError('word out of range')
    return bytes((n & 255, n >> 8))


def immediate(n, radix=10):
    if radix == 16:
        return bytes((HEX16,)) + word(n)
    if not 0 <= n <= 65535:
        raise SourceError('literal out of range')
    if n < 16:
        return bytes((0x70+n,))
    if n < 256:
        return bytes((DEC8, n))
    return bytes((DEC16,)) + word(n)


def name_token(i):
    if not 0 <= i < 65535:
        raise SourceError('invalid name ID')
    return bytes((0x80+i,)) if i < 128 else bytes((NAME16,)) + word(i)


def raw(code, s):
    if isinstance(s, str):
        s = s.encode('latin-1')
    if len(s) > 255:
        raise SourceError('payload too long')
    return bytes((code, len(s))) + s


@dataclass(frozen=True)
class Token:
    code: int
    value: object = None
    offset: int = 0
    end: int = 0

    @property
    def spelling(self):
        return SPELLINGS.get(self.code)


def decode(stream, names, validate_context=True):
    """Validate canonical encodings before permitting traversal/publication."""
    if not 1 <= len(stream) <= 255:
        raise SourceError('line token length must be 1..255')
    result, p = [], 0
    while p < len(stream):
        start = p
        c = stream[p]
        p += 1
        v = None
        if c in RAW:
            if p == len(stream):
                raise SourceError('missing raw length')
            n = stream[p]
            p += 1
            if p+n > len(stream) or (not n and c in {NUMTEXT, BADTEXT, DATA_SPELLING}):
                raise SourceError('invalid raw payload')
            v = stream[p:p+n]
            p += n
            if c == STRING and b'"' in v:
                raise SourceError('quote inside STRING')
        elif c in (DEC8, DEC16, HEX16, NAME16):
            n = 1 if c == DEC8 else 2
            if p+n > len(stream):
                raise SourceError('truncated integer/ID')
            v = int.from_bytes(stream[p:p+n], 'little')
            p += n
            if (c == DEC8 and v < 16) or (c == DEC16 and v < 256):
                raise SourceError('nonminimal decimal encoding')
            if c == NAME16:
                if v < 128 or v == 65535:
                    raise SourceError('noncanonical name ID')
                names[v]
        elif 0x70 <= c <= 0x7f:
            v = c-0x70
        elif c >= 0x80:
            v = c-0x80
            names[v]
        elif c not in SPELLINGS:
            raise SourceError('reserved token')
        result.append(Token(c, v, start, p))
    if validate_context:
        _validate_context(result)
    return result


def is_number(t):
    return t.code in (DEC8, DEC16, HEX16) or 0x70 <= t.code <= 0x7f


def number_text(t):
    return f'${t.value:04X}' if t.code == HEX16 else str(t.value)


def _numeric_field(ts):
    sign = ''
    if ts and ts[0].code in (5, 6):
        sign = ts[0].spelling
        ts = ts[1:]
    if len(ts) != 1 or not is_number(ts[0]):
        return None
    return sign + number_text(ts[0])


def _validate_context(ts):
    in_data, field = False, []
    for i, t in enumerate(ts):
        if t.code == CODES['REM']:
            if i+2 != len(ts) or ts[i+1].code != REMTEXT:
                raise SourceError('REM must end in one REMTEXT')
        if t.code == REMTEXT:
            if not i or ts[i-1].code != CODES['REM']:
                raise SourceError('orphan REMTEXT')
        if t.code == CODES['DATA']:
            in_data, field = True, []
            continue
        if t.code == 0:
            in_data, field = False, []
            continue
        if in_data and t.code == 1:
            field = []
            continue
        if t.code in (DATA_TEXT, DATA_SPELLING) and not in_data:
            raise SourceError('DATA payload outside DATA')
        if t.code == DATA_TEXT:
            if any(c in t.value for c in (b'"', b',', b':', b'\r', b'\n')):
                raise SourceError('delimiter inside DATA_TEXT')
            s = t.value.decode('latin-1')
            if NUM_RE.fullmatch(s.strip()) or re.match(r'^[+-]?(?:[0-9]|\$)', s.strip()):
                raise SourceError('numeric DATA hidden in DATA_TEXT')
        if t.code == DATA_SPELLING:
            canonical = _numeric_field(field)
            s = t.value.decode('latin-1')
            m = NUM_RE.fullmatch(s)
            if canonical is None or not m:
                raise SourceError('invalid DATA_SPELLING')
            sign, n = m.groups()
            radix = 16 if n.startswith('$') else 10
            v = int(n[1:] if radix == 16 else n, radix)
            expected = (sign + (f'${v:04X}' if radix == 16 else str(v)))
            if v > 65535 or expected != canonical or s == canonical:
                raise SourceError('DATA_SPELLING mismatch/redundancy')
        if in_data:
            field.append(t)


def _data_field(s):
    s = s.strip()
    if s.startswith('"'):
        if s.endswith('"') and len(s) > 1:
            return raw(STRING, s[1:-1])
        return raw(STRING, s[1:])
    m = NUM_RE.fullmatch(s)
    if m:
        sign, n = m.groups()
        radix = 16 if n.startswith('$') else 10
        v = int(n[1:] if radix == 16 else n, radix)
        if v > 65535:
            return raw(NUMTEXT, s)
        b = (bytes((CODES[sign],)) if sign else b'') + immediate(v, radix)
        canonical = sign + (f'${v:04X}' if radix == 16 else str(v))
        return b + (raw(DATA_SPELLING, s) if s != canonical else b'')
    if re.match(r'^[+-]?(?:[0-9]|\$|\.[0-9])', s):
        return raw(NUMTEXT if not s.startswith('$') else BADTEXT, s)
    return raw(DATA_TEXT, s)


def tokenize(source, names, interactive=False):
    if interactive and len(source) > 80:
        raise SourceError('interactive line exceeds 80 characters')
    staged = names.copy()
    out = bytearray()
    p = 0
    while p < len(source):
        c = source[p]
        if c in ' \t':
            p += 1
            continue
        if c == '"':
            end = source.find('"', p+1)
            if end < 0:
                end = len(source)
            out += raw(STRING, source[p+1:end])
            p = min(end+1, len(source))
            continue
        if c == '?':
            out.append(CODES['PRINT'])
            p += 1
            continue
        if c.isascii() and c.isalpha():
            m = re.match(r'[A-Za-z][A-Za-z0-9]*[%$]?', source[p:])
            spelling = m[0].upper()
            p += len(m[0])
            if p<len(source) and 0xc1<=ord(source[p])<=0xda:
                prefix=spelling+chr(ord(source[p])&0x7f)
                p+=1
                choices=[k for k in KEYWORDS if k.startswith(prefix)
                         and (not k.endswith(('#','(')) or
                              (p<len(source) and source[p]==k[-1]))]
                if choices and (p==len(source) or not source[p].isalnum()):
                    spelling=choices[0]
                else:
                    out+=raw(BADTEXT,prefix)
                    continue
                if spelling.endswith(('#','(')):
                    p+=1
            if p < len(source) and source[p] == '#' and spelling in ('PRINT', 'INPUT', 'GET'):
                spelling += '#'
                p += 1
            if spelling in ('TAB', 'SPC') and p < len(source) and source[p] == '(':
                spelling += '('
                p += 1
            # Text shortcut P., G., etc; PETSCII shifted final letter also supported.
            if p < len(source) and source[p] == '.':
                choices = [k for k in KEYWORDS if k.startswith(spelling)]
                if choices and (p+1 == len(source) or not source[p+1].isalnum()):
                    spelling = choices[0]
                    p += 1
            if spelling in CODES:
                out.append(CODES[spelling])
                if spelling == 'REM':
                    remainder = source[p:]
                    if remainder.startswith(' '):
                        remainder = remainder[1:]
                    out += raw(REMTEXT, remainder)
                    p = len(source)
                elif spelling == 'DATA':
                    start, quoted = p, False
                    while p <= len(source):
                        if p == len(source) or (not quoted and source[p] in ',:'):
                            out += _data_field(source[start:p])
                            if p == len(source) or source[p] == ':':
                                break
                            out.append(1)
                            start = p+1
                        elif source[p] == '"':
                            quoted = not quoted
                        p += 1
            else:
                out += name_token(staged.add(spelling))
            continue
        if c == 'π':
            out.append(CODES['π'])
            p += 1
            continue
        if c.isdigit() and c.isascii() or c == '$' or c == '.' and p+1 < len(source) and source[p+1].isdigit():
            m = re.match(r'\$[A-Za-z0-9]*|(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?[A-Za-z0-9]*', source[p:])
            s = m[0]
            p += len(s)
            radix = 16 if s.startswith('$') else 10
            digits = s[1:] if radix == 16 else s
            valid = bool(re.fullmatch('[0-9A-Fa-f]+' if radix == 16 else '[0-9]+', digits))
            if valid:
                n = int(digits, radix)
                if n <= 65535 and (radix == 10 or len(digits) <= 4):
                    out += immediate(n, radix)
                else:
                    out += raw(NUMTEXT, s)
            else:
                out += raw(NUMTEXT if re.fullmatch(r'(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?', s) else BADTEXT, s)
            continue
        pair = source[p:p+2]
        if pair in ('><', '=<', '=>'):
            pair = {'><':'<>', '=<':'<=', '=>':'>='}[pair]
        if pair in CODES:
            out.append(CODES[pair])
            p += 2
        elif c in CODES:
            out.append(CODES[c])
            p += 1
        else:
            out += raw(BADTEXT, c)
            p += 1
    decode(bytes(out), staged)
    names.names, names.ids = staged.names, staged.ids
    return bytes(out)


def listing(stream, names):
    ts = decode(stream, names)
    parts, i, data = [], 0, False
    while i < len(ts):
        t = ts[i]
        if t.code == CODES['DATA']:
            data = True
        if t.code == 0:
            data = False
        if data and (is_number(t) or t.code in (5, 6)):
            end = i+1
            if t.code in (5, 6) and end < len(ts) and is_number(ts[end]):
                end += 1
            if end < len(ts) and ts[end].code == DATA_SPELLING:
                parts.append(ts[end].value.decode('latin-1'))
                i = end+1
                continue
            s = _numeric_field(ts[i:end])
            if s is not None:
                parts.append(s)
                i = end
                continue
        if is_number(t):
            s = number_text(t)
        elif t.code >= 0x80 or t.code == NAME16:
            s = names[t.value]
        elif t.code == STRING:
            s = '"' + t.value.decode('latin-1') + '"'
        elif t.code in RAW:
            s = t.value.decode('latin-1')
        else:
            s = t.spelling
        parts.append(s)
        i += 1
    # Whitespace is generated only between tokens, never inside payloads.
    result = ''
    previous = None
    for s in parts:
        if previous is None:
            result = s
        elif s in (')', ',', ';'):
            result += s
        elif previous in ('(', 'TAB(', 'SPC('):
            result += s
        else:
            result += ' ' + s
        previous = s
    return result


def remap(stream, names, mapping):
    out = bytearray()
    for t in decode(stream, names):
        if t.code >= 0x80 or t.code == NAME16:
            out += name_token(mapping[t.value])
        else:
            out += stream[t.offset:t.end]
    return bytes(out)
