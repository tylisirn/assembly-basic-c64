"""Deterministic LZSS: flag byte, 8 literal/match items, 12-bit distance/4-bit length.

A set flag means a literal. A match packs (distance-1) low 12 bits,
(length-3) high 4 bits. Output size is supplied separately by the linker.
"""
def compress(data):
    # Minimize encoded bytes including the flag byte every eight items. Greedy
    # longest-match parsing can waste cartridge space at short-match boundaries.
    size = len(data)
    matches = []
    for p in range(size):
        best_len = 0
        best_dist = 0
        for q in range(p - 1, max(-1, p - 4097), -1):
            if data[q] != data[p]:
                continue
            n = 1
            while n < 18 and p + n < size and data[q + n] == data[p + n]:
                n += 1
            if n > best_len:
                best_len, best_dist = n, p - q
                if n == 18:
                    break
        matches.append((best_len, best_dist))
    costs = [[0] * 8 for _ in range(size + 1)]
    choices = [[1] * 8 for _ in range(size)]
    for p in range(size - 1, -1, -1):
        for bit in range(8):
            next_bit = (bit + 1) % 8
            cost = 1 + costs[p + 1][next_bit]
            length = 1
            for n in range(3, matches[p][0] + 1):
                candidate = 2 + costs[p + n][next_bit]
                if candidate <= cost:
                    cost, length = candidate, n
            costs[p][bit] = cost + (bit == 0)
            choices[p][bit] = length
    out = bytearray()
    p = 0
    while p < size:
        flag_at = len(out)
        out.append(0)
        for bit in range(8):
            if p == size:
                break
            n = choices[p][bit]
            if n == 1:
                out[flag_at] |= 1 << bit
                out.append(data[p])
            else:
                value = (matches[p][1] - 1) | ((n - 3) << 12)
                out.extend((value & 255, value >> 8))
            p += n
    return bytes(out)


def decompress(data,size):
    out=bytearray();p=0
    while len(out)<size:
        flags=data[p];p+=1
        for bit in range(8):
            if len(out)==size:break
            if flags & 1<<bit:
                out.append(data[p]);p+=1
            else:
                v=data[p]|data[p+1]<<8;p+=2
                distance=(v&4095)+1;n=(v>>12)+3
                if distance>len(out) or len(out)+n>size:raise ValueError('invalid match')
                for _ in range(n):out.append(out[-distance])
    if p!=len(data):raise ValueError('trailing compressed bytes')
    return bytes(out)
