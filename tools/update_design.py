#!/usr/bin/env python3
"""Synchronize implementation facts in the DOCX while preserving its package.

The original design remains available in Git. Appendix B is replaced on every
run; future version-one requirements are retained and explicitly marked pending.
"""
from pathlib import Path
import hashlib
import json
import io
import xml.etree.ElementTree as ET
import zipfile
ROOT=Path(__file__).resolve().parents[1]
DOC=ROOT/'Assembly_BASIC_C64_Design.docx'
W='http://schemas.openxmlformats.org/wordprocessingml/2006/main'
NS={'w':W}
ET.register_namespace('w',W)

def namespaces(data):
    result=dict(value for _,value in ET.iterparse(io.BytesIO(data),events=['start-ns']))
    for prefix,uri in result.items():ET.register_namespace(prefix,uri)
    return result

def serialize(root,declared):
    data=ET.tostring(root,encoding='utf-8',xml_declaration=True)
    # Preserve unused declarations, including prefixes named by mc:Ignorable.
    extras=''.join(f' xmlns:{p}="{uri}"' for p,uri in declared.items()
                   if p and f'xmlns:{p}='.encode() not in data)
    end=data.index(b'>',data.index(b'?>')+2)
    return data[:end]+extras.encode()+data[end:]

def paragraph(text,heading=False):
    p=ET.Element(f'{{{W}}}p')
    if heading:
        properties=ET.SubElement(p,f'{{{W}}}pPr')
        ET.SubElement(properties,f'{{{W}}}pStyle',{f'{{{W}}}val':'Heading1'})
    run=ET.SubElement(p,f'{{{W}}}r')
    t=ET.SubElement(run,f'{{{W}}}t')
    t.text=text;t.set('{http://www.w3.org/XML/1998/namespace}space','preserve')
    return p

def synchronize():
    report=json.loads((ROOT/'build/size-report.json').read_text())
    tests=json.loads((ROOT/'build/test-report.json').read_text())
    assert tests['failures']==tests['errors']==0, 'Fix test failures before synchronizing the design'
    assert tests['rom_sha256']==report['rom_sha256'], 'Tests refer to a different cartridge build'
    with zipfile.ZipFile(DOC) as z:
        entries=[(info,z.read(info.filename)) for info in z.infolist()]
    original=dict((i.filename,b) for i,b in entries)['word/document.xml']
    declared=namespaces(original)
    root=ET.fromstring(original)
    body=root.find('w:body',NS)
    for child in list(body):
        value=''.join(child.itertext())
        if value.startswith('Appendix B — implementation status'):
            start=list(body).index(child)
            for old in list(body)[start:]:
                if old.tag!=f'{{{W}}}sectPr':body.remove(old)
            break
    replacements={
        'Design specification  |  Version 0.3  |  9 October 2026':
        'Design specification  |  Version 0.4  |  9 October 2026',
        '$E800-$FFF9':'$E400-$FFF9', '$E000-$E7FF':'$E000-$E3FF',
        '[$E000,$E800)':'[$E000,$E400)', '49 KiB':'48 KiB',
        '6138 bytes':'7162 bytes', '6138':'7162',
        'proposed $E800 base':'implemented $E400 base',
        'roughly 389 such lines':'roughly 379 such lines',
    }
    rewrites={
        'Link the execution image for its fixed run addresses':
        'Link the execution image for fixed run addresses $E400-$FFF9 (runtime ABI 2). Store a deterministic LZSS-compressed load image in the standard cartridge and decompress it through common-RAM read gates at cold start, RUN and CONT. The linker emits the RAM runtime as a separate fixed-address binary before compression; all internal calls already name its RAM run addresses. Copy the complete dependency closure, including helper code, tables, constants and diagnostics. No arbitrary relocation of ROM instructions is assumed.',
        'The allocator therefore has two spans:':
        'The implemented allocator has two spans: [$1400,$D000) and [$E000,$E400). Their raw total is 48 KiB (49152 bytes), before anchors, names, source, generated code, arrays, strings and free-block overhead. The $E000-$E3FF shadow span supplies 1 KiB; $E400-$FFFF is permanently reserved for the runtime and six vector bytes. This is the lower-runtime-base adjustment permitted by the original design.',
        'These sizes are proposed budgets.':
        'These are ABI 2 build limits. Runtime helpers have 7162 bytes at $E400-$FFF9; the measured image occupies 6386 bytes. Any future runtime-base change requires a new ABI/build identifier and recompilation. ROM-off execution remains required. No allocation may cross the I/O hole, overlap the runtime or assume visibility during a ROM gateway.',
        'Runtime string collection may move string payloads':
        'The implemented runtime collector is nonmoving mark-and-sweep with free-list coalescing. It never moves string payloads, line code or native return addresses. It enumerates physical allocation boundaries and retains objects reachable from source, slabs, names/bindings, arrays/functions, descriptors, expression temporaries and live helper roots. It runs wholly within copied RAM helpers. Fragmentation can prevent allocation despite sufficient total free bytes. Stopped code compaction/rebuild remains planned and is not implemented.',
        'Use compacting mark-and-copy or sliding collection':
        'Use the implemented nonmoving mark-and-sweep collector with registered descriptor and helper roots. Roots include scalar cells, array elements, expression temporaries and function state. Allocating helpers must publish temporary string pointers before a collection boundary. Pointer rewriting is unnecessary because payloads remain stationary; the tradeoff is fragmentation. Clear temporary roots at statement completion and error exit.',
        'Intern each full normalized spelling into a name dictionary':
        'Intern each complete normalized spelling into a dictionary with a one-byte length, full name bytes and a 16-bit ID. The implementation compares complete spellings in a linked dictionary rather than using the proposed hash buckets. This has linear compile-time lookup cost but preserves every character and suffix. Scalar cells and separate array/function bindings remain stable; repeated source references carry IDs rather than repeated spellings. A, A% and A$ and SCORE and SCORETOTAL remain distinct.',
        'Bind all references during compilation so ordinary scalar accesses':
        'Bind scalar references during compilation so native accesses name stable cells without runtime full-name lookup. Dictionary lookup and storage grow with complete spellings; repeated token references remain compact. Retain interned names and cells until NEW or a future complete stopped rebuild that rebinds all source and code. Deletion cannot free a cell still referenced by native code. RUN clears values while retaining bindings.',
        'These are planning allocations, not measured sizes.':
        'The preceding subdivision is the original planning allocation. ABI 2 measured link sizes are recorded in Appendix B and dist/size-report.json. The compressed runtime consumes ROM as well as 6386 bytes in its 7162-byte RAM reservation. Gateway code consumes both low-RAM workspace and cartridge space. The build enforces the 16384-byte cartridge, 768-byte gateway and 7162-byte runtime limits.',
    }
    rewrites['These sizes are proposed budgets.']=rewrites['These sizes are proposed budgets.'].replace('6386',str(report['runtime_used_bytes']))
    rewrites['These are ABI 2 build limits.']=rewrites['These sizes are proposed budgets.']
    measured=('The preceding subdivision is the original planning allocation. ABI 2 measured link sizes '
              'are recorded in Appendix B and dist/size-report.json. The compressed runtime consumes ROM '
              f"as well as {report['runtime_used_bytes']} bytes in its {report['runtime_budget_bytes']}-byte "
              'RAM reservation. Gateway code consumes both low-RAM workspace and cartridge space. '
              'The build enforces the 16384-byte cartridge, 768-byte gateway and 7162-byte runtime limits.')
    rewrites['These are planning allocations, not measured sizes.']=measured
    rewrites['The preceding subdivision is the original planning allocation.']=measured
    paragraphs=list(body.iter(f'{{{W}}}p'))
    for p in paragraphs:
        nodes=list(p.iter(f'{{{W}}}t'))
        if not nodes:continue
        value=''.join(n.text or '' for n in nodes)
        revised=value
        for a,b in replacements.items():revised=revised.replace(a,b)
        for prefix,text in rewrites.items():
            if revised.startswith(prefix):revised=text;break
        if revised!=value:
            nodes[0].text=revised
            for n in nodes[1:]:n.text=''
    status_line=('Implementation status: working development cartridge; the full version-one '
                 'release is not complete. See Appendix B for measured implementation '
                 'facts, explicit differences and pending acceptance work.')
    if not any(''.join(p.itertext()).startswith('Implementation status:') for p in body):
        body.insert(2,paragraph(status_line))
    for row in root.findall('.//w:tr',NS):
        cells=row.findall('w:tc',NS)
        if len(cells)<2:continue
        address=''.join(n.text or '' for n in cells[0].iter(f'{{{W}}}t'))
        if address=='$E000-$E3FF':
            ts=list(cells[1].iter(f'{{{W}}}t'));ts[0].text='1 KB RAM'
            for t in ts[1:]:t.text=''
    marker='Appendix B — implementation status, revision 0.4'
    additions=[paragraph(marker,True),paragraph(
        'This appendix records the development implementation on 9 October 2026. '
        'The full version-one contract is not yet complete. Original release '
        'requirements above remain the target unless an architectural choice is '
        'explicitly revised here. Original revision 0.3 is preserved in Git commit 9480026.'),
        paragraph('Measured linked build: '+json.dumps(report,sort_keys=True)),
        paragraph(f"Automated validation: {tests['tests_run']} tests passed, "
                  f"{tests['runtime_instructions_checked']} documented runtime instructions checked. "
                  'Environment: instruction-level py65 with deterministic KERNAL stubs; '
                  'this is not cycle-accurate or physical-machine acceptance evidence.'),
        paragraph('Source/container version 1 and runtime ABI 2 are distinct. '
                  'Language zero page is $02-$78; common workspace is $0800-$13FF. '
                  'Function activations currently use a guarded hardware stack with depth eight. '
                  'The compiler emits native helper calls and branches, without the proposed inline scalar optimizations.')]
    measurements=json.loads((ROOT/'docs/measurements.json').read_text())
    assert measurements['rom_sha256']==report['rom_sha256'], 'Measurements refer to a different cartridge'
    additions.append(paragraph('Instruction-level measurements and capacity scenario: '+
                               json.dumps(measurements,sort_keys=True)))
    status=(ROOT/'docs/IMPLEMENTATION_STATUS.md').read_text()
    for line in status.splitlines():
        if not line or line.startswith('| ---'):continue
        if line.startswith('#'):additions.append(paragraph(line.lstrip('# '),True))
        elif line.startswith('|'):
            fields=[f.strip() for f in line.strip('|').split('|')]
            additions.append(paragraph(' — '.join(fields)))
        else:additions.append(paragraph(line.lstrip('- ')))
    section=body.find('w:sectPr',NS)
    position=list(body).index(section) if section is not None else len(body)
    for p in additions:body.insert(position,p);position+=1
    xml=serialize(root,declared)
    temporary=DOC.with_suffix('.docx.tmp')
    with zipfile.ZipFile(temporary,'w') as z:
        for info,data in entries:
            if info.filename=='word/document.xml':data=xml
            elif info.filename=='docProps/core.xml':
                core_namespaces=namespaces(data)
                core=ET.fromstring(data)
                for n in core:
                    if n.tag.endswith('}revision'):n.text='4'
                    if n.tag.endswith('}modified'):n.text='2026-10-09T00:00:00Z'
                data=serialize(core,core_namespaces)
            z.writestr(info,data)
    with zipfile.ZipFile(temporary) as z:
        assert z.testzip() is None
        for name in z.namelist():
            if name.endswith('.xml'):ET.fromstring(z.read(name))
    temporary.replace(DOC)
    text='\n'.join(''.join(n.text or '' for n in p.iter(f'{{{W}}}t'))
                   for p in root.iter(f'{{{W}}}p'))+'\n'
    (ROOT/'docs/Assembly_BASIC_C64_Design.txt').write_text(text)
    (ROOT/'docs/design-sync.json').write_text(json.dumps({
        'design_revision':'0.4','runtime_abi':report['runtime_abi'],
        'design_sha256':hashlib.sha256(DOC.read_bytes()).hexdigest(),
        'rom_sha256':report['rom_sha256'],'runtime_run_address':report['runtime_run_address'],
        'arena_raw_bytes':report['arena_raw_bytes']},indent=2)+'\n')
    print('Updated design revision 0.4 and readable export; original revision remains in Git.')

if __name__=='__main__':synchronize()
