"""Deterministic LZSS: flag byte, 8 literal/match items, 12-bit distance/4-bit length.

A set flag means a literal. A match packs (distance-1) low 12 bits,
(length-3) high 4 bits. Output size is supplied separately by the linker.
"""
def compress(data):
    out=bytearray();p=0
    while p<len(data):
        flag_at=len(out);out.append(0);flags=0
        for bit in range(8):
            if p==len(data):break
            best_len=0;best_dist=0
            # Only deterministic nearest occurrence ties; overlapping copies allowed.
            for q in range(p-1,max(-1,p-4097),-1):
                if data[q]!=data[p]:continue
                n=1
                while n<18 and p+n<len(data) and data[q+n]==data[p+n]:n+=1
                if n>best_len:
                    best_len,best_dist=n,p-q
                    if n==18:break
            if best_len>=3:
                v=(best_dist-1)|((best_len-3)<<12)
                out.extend((v&255,v>>8));p+=best_len
            else:
                flags|=1<<bit;out.append(data[p]);p+=1
        out[flag_at]=flags
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
