#!/usr/bin/env python3
"""Publish the built development cartridge only with matching validation/design facts."""
from pathlib import Path
import hashlib
import json
import re
import shutil
import sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'host'))
from ab64.cli import text_program
from ab64.container import dumps

def package():
    report=json.loads((ROOT/'build/size-report.json').read_text())
    tests=json.loads((ROOT/'build/test-report.json').read_text())
    sync=json.loads((ROOT/'docs/design-sync.json').read_text())
    assert tests['failures']==tests['errors']==0, 'Fix regression failures before packaging'
    assert tests['rom_sha256']==sync['rom_sha256']==report['rom_sha256']
    assert hashlib.sha256((ROOT/'build/assembly-basic.bin').read_bytes()).hexdigest()==report['rom_sha256']
    assert hashlib.sha256((ROOT/'Assembly_BASIC_C64_Design.docx').read_bytes()).hexdigest()==sync['design_sha256']
    destination=ROOT/'dist';destination.mkdir(exist_ok=True)
    for name in ('assembly-basic.bin','assembly-basic.crt','size-report.json','test-report.json'):
        shutil.copyfile(ROOT/'build'/name,destination/name)
    labels={}
    for line in (ROOT/'build/assembly-basic.lbl').read_text().splitlines():
        match=re.match(r'al ([0-9A-Fa-f]+) \.(.+)',line)
        if match:labels[match[2]]=int(match[1],16)
    abi={'runtime_abi':report['runtime_abi'],'rom_sha256':report['rom_sha256'],
         'cartridge_type':report['cartridge_type'],'cartridge_format':report['cartridge_format'],
         'bank_register':report['bank_register'],'bank_shadow':0xbe3,'banks':report['banks'],
         'command_bank':0,'command_port_bits':7,'execution_port_bits':5,'runtime_base':0xe400,
         'language_zero_page':[2,121],'workspace':[0x800,0x1400],
         'resident_compiler':[0x1400,0x2c00],
         'image_loads':{image.lower():{'bank':bank,'rom_address':labels[f'__{image}_LOAD__'],
                                      'run_address':labels[f'__{image}_RUN__'],
                                      'bytes':labels[f'__{image}_SIZE__'],'encoding':'raw'}
                        for image,bank in (('COMPILER',1),('RUNTIME',2))},
         'gateways':{n:labels[n] for n in ('kernal_gate','enter_ready','sys_gateway','usr_gateway',
                     'file_entry','select_command_bank','copy_bank_image','bank_cold','bank_warm')},
         'runtime_entries':{n:v for n,v in sorted(labels.items())
                            if re.fullmatch('[a-z][a-z_0-9]*',n)
                            and 0xe400<=v<0xe400+report['runtime_used_bytes']}}
    (destination/'abi.json').write_text(json.dumps(abi,indent=2)+'\n')
    (destination/'examples').mkdir(exist_ok=True)
    for example in sorted((ROOT/'examples').glob('*.bas')):
        data=dumps(*text_program(example.read_text(encoding='latin-1')))
        (destination/'examples'/example.with_suffix('.ab').name).write_bytes(data)
    manifest={'status':'development; version-one release acceptance incomplete',
              'design_revision':sync['design_revision'],'runtime_abi':report['runtime_abi'],
              'cartridge_type':report['cartridge_type'],'source_version':1,
              'validated_tests':tests['tests_run'],'artifacts':{}}
    for path in sorted(destination.rglob('*')):
        if path.is_file() and path.name!='manifest.json':
            data=path.read_bytes()
            manifest['artifacts'][str(path.relative_to(destination))]={'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()}
    (destination/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(f"Packaged revision {sync['design_revision']}: {tests['tests_run']} tests, ROM {report['rom_sha256']}")

if __name__=='__main__':package()
