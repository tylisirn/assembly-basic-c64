"""Source exchange utilities; native compilation remains on the cartridge CPU."""
import argparse
from pathlib import Path
import re
import sys
from .tokens import Names,SourceError,listing,tokenize
from .container import dumps,loads


def text_program(text):
    names=Names();lines={}
    for row in text.splitlines():
        if not row.strip():continue
        m=re.fullmatch(r'\s*([0-9]+)(?:\s+(.*))?',row)
        if not m or not 0<=int(m[1])<=63999:
            raise SourceError('text input requires decimal numbered lines 0..63999')
        number=int(m[1]);source=m[2] or ''
        if source.strip():lines[number]=tokenize(source,names)
        else:lines.pop(number,None)
    return names,lines


def main(argv=None):
    p=argparse.ArgumentParser(description='Assembly BASIC C64 source tools')
    sub=p.add_subparsers(dest='command',required=True)
    for cmd in ('encode','decode'):
        q=sub.add_parser(cmd)
        q.add_argument('input',type=Path)
        q.add_argument('output',type=Path)
    q=sub.add_parser('verify');q.add_argument('first',type=Path);q.add_argument('second',type=Path)
    q=sub.add_parser('run',help='run native cartridge code with deterministic KERNAL stubs')
    q.add_argument('input',type=Path)
    q=sub.add_parser('repl',help='instruction-level cartridge console (not cycle accurate)')
    args=p.parse_args(argv)
    try:
        if args.command=='encode':
            n,ll=text_program(args.input.read_text(encoding='latin-1'))
            args.output.write_bytes(dumps(n,ll))
        elif args.command=='decode':
            n,ll=loads(args.input.read_bytes())
            text=''.join(f'{i} {listing(s,n)}\n' for i,s in ll.items())
            args.output.write_text(text,encoding='latin-1')
        elif args.command=='verify':
            a=dumps(*loads(args.first.read_bytes()));b=dumps(*loads(args.second.read_bytes()))
            print('SOURCE MATCHES' if a==b else 'SOURCE DIFFERS')
            return 0 if a==b else 1
        else:
            from .emulator import Machine
            m=Machine().boot()
            if args.command=='run':
                data=args.input.read_bytes()
                if not data.startswith(b'AB64SRC\0'):
                    data=dumps(*text_program(data.decode('latin-1')))
                loads(data)
                m.files['PROGRAM.AB']=bytearray(data)
                start=len(m.output)
                m.input.extend(b'LOAD "PROGRAM.AB"\r')
                m.pump(max(2000000,len(data)*800))
                result=bytes(m.output[start:]).decode('latin-1')
                if m.errors:raise SourceError(result.strip())
                result=m.command('RUN').replace('\r','\n')
                print(result.rsplit('\nREADY.\n',1)[0],end='')
                return 1 if m.errors else 0
            print(bytes(m.output).decode('latin-1').replace('\r','\n'),end='')
            while True:
                try:line=input()
                except EOFError:break
                print(m.command(line).replace('\r','\n'),end='')
    except (SourceError,OSError,AssertionError) as e:
        p.exit(1,f'ab64: {e}\n')
    return 0
