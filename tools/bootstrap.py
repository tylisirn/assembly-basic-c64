#!/usr/bin/env python3
"""Optional Linux/amd64 local tool bootstrap. No sudo or global installation."""
import hashlib
from pathlib import Path
import platform
import subprocess
import urllib.request
import zipfile
ROOT=Path(__file__).resolve().parents[1]
DOWNLOADS=[
 ('cc65.deb','https://deb.debian.org/debian/pool/main/c/cc65/cc65_2.19-2_amd64.deb','b3923a7a4a434e3cefc9a1e444b3b799893341b006c708a2ec3eb1ff91ef8b0f'),
 ('py65.whl','https://files.pythonhosted.org/packages/f6/3d/7171f8401bb3cf058d233af314d3e314a348488bd22b2143b3591566a172/py65-1.2.0-py2.py3-none-any.whl','8e51f149647f2c2b44e5eb54350057771ccaef97f5f3d593fa3737e44c1ce4b7')]

def main():
    if platform.system()!='Linux' or platform.machine() not in ('x86_64','AMD64'):
        raise SystemExit('Bootstrap targets Linux amd64. Install cc65 and py65 manually on other platforms.')
    target=ROOT/'.tools';target.mkdir(exist_ok=True)
    for name,url,digest in DOWNLOADS:
        file=target/name
        if not file.exists():
            with urllib.request.urlopen(url,timeout=60) as response:
                file.write_bytes(response.read())
        if hashlib.sha256(file.read_bytes()).hexdigest()!=digest:
            raise SystemExit(f'Checksum mismatch: {file}')
    subprocess.run(['dpkg-deb','-x',str(target/'cc65.deb'),str(target/'cc65')],check=True)
    with zipfile.ZipFile(target/'py65.whl') as z:z.extractall(target/'py65')
    print('Local tools ready. Run python3 tools/build.py and python3 tools/test.py.')

if __name__=='__main__':main()
