#!/usr/bin/env python3
"""Synchronize implementation facts in the DOCX while preserving its package.

The original design remains available in Git. Appendix B is replaced on every
run; future version-one requirements are retained and explicitly marked pending.
"""
from pathlib import Path
import copy
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
    design_before=hashlib.sha256(DOC.read_bytes()).hexdigest()
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
        'Design specification  |  Version 0.5  |  9 October 2026',
        '$E800-$FFF9':'$E400-$FFF9', '$E000-$E7FF':'$E000-$E3FF',
        '[$E000,$E800)':'[$E000,$E400)', '49 KiB':'42 KiB', '48 KiB':'42 KiB',
        'Version 0.4':'Version 0.5', 'runtime ABI 2':'runtime ABI 3', 'ABI 2':'ABI 3',
        'roughly 379 such lines':'roughly 322 such lines',
        '6138 bytes':'7162 bytes', '6138':'7162',
        'proposed $E800 base':'implemented $E400 base',
        'roughly 389 such lines':'roughly 322 such lines',
    }
    rewrites={
        'Link the execution image for its fixed run addresses':
        'Link the execution runtime for fixed run addresses $E400-$FFF9 and the resident compiler for $1400-$2BFF (runtime ABI 3). Store a deterministic LZSS-compressed load image in the standard cartridge and decompress it through common-RAM read gates at cold start; refresh the runtime at RUN and CONT. Both images have separate fixed-address link outputs. The linker emits the RAM runtime as a separate fixed-address binary before compression; all internal calls already name its RAM run addresses. Copy the complete dependency closure, including helper code, tables, constants and diagnostics. No arbitrary relocation of ROM instructions is assumed.',
        'The allocator therefore has two spans:':
        'The implemented allocator has two spans: [$2C00,$D000) and [$E000,$E400). Their raw total is 42 KiB (43008 bytes), before anchors, names, source, generated code, arrays, strings and free-block overhead. The $1400-$2BFF range is permanently reserved for a 6 KiB compiler image decompressed at startup. The $E000-$E3FF shadow span supplies 1 KiB; $E400-$FFFF is permanently reserved for the runtime and six vector bytes. This is the lower-runtime-base adjustment permitted by the original design.',
        'These sizes are proposed budgets.':
        'These are ABI 3 build limits. Runtime helpers have 7162 bytes at $E400-$FFF9; the measured image occupies 6386 bytes. Any future runtime-base change requires a new ABI/build identifier and recompilation. ROM-off execution remains required. No allocation may cross the I/O hole, overlap the runtime or assume visibility during a ROM gateway.',
        'Runtime string collection may move string payloads':
        'The implemented runtime collector is nonmoving mark-and-sweep with free-list coalescing. It never moves string payloads, line code or native return addresses. It enumerates physical allocation boundaries and retains objects reachable from source, slabs, names/bindings, arrays/functions, descriptors, expression temporaries and live helper roots. It runs wholly within copied RAM helpers. Fragmentation can prevent allocation despite sufficient total free bytes. Direct CLEAN now rebuilds source, anchors and bindings into a second graph, densely remaps names, clears values/continuations and collects the released graph. It requires temporary headroom; general sliding arena compaction remains pending.',
        'Use compacting mark-and-copy or sliding collection':
        'Use the implemented nonmoving mark-and-sweep collector with registered descriptor and helper roots. Roots include scalar cells, array elements, expression temporaries and function state. Allocating helpers must publish temporary string pointers before a collection boundary. Pointer rewriting is unnecessary because payloads remain stationary; the tradeoff is fragmentation. Clear temporary roots at statement completion and error exit.',
        'Intern each full normalized spelling into a name dictionary':
        'Intern each complete normalized spelling into a dictionary with a one-byte length, full name bytes and a 16-bit ID. The implementation compares complete spellings in a linked dictionary rather than using the proposed hash buckets. This has linear compile-time lookup cost but preserves every character and suffix. Scalar cells and separate array/function bindings remain stable; repeated source references carry IDs rather than repeated spellings. A, A% and A$ and SCORE and SCORETOTAL remain distinct.',
        'Bind all references during compilation so ordinary scalar accesses':
        'Bind scalar references during compilation so native accesses name stable cells without runtime full-name lookup. Dictionary lookup and storage grow with complete spellings; repeated token references remain compact. Retain interned names and cells until NEW or a successful CLEAN rebuild that rebinds all source and code. Deletion cannot free a cell still referenced by native code. RUN clears values while retaining bindings.',
        'These are planning allocations, not measured sizes.':
        'The preceding subdivision is the original planning allocation. ABI 3 measured link sizes are recorded in Appendix B and dist/size-report.json. The compressed runtime consumes ROM as well as 6386 bytes in its 7162-byte RAM reservation. Gateway code consumes both low-RAM workspace and cartridge space. The build enforces the 16384-byte cartridge, 768-byte gateway and 7162-byte runtime limits.',
    }
    rewrites['These sizes are proposed budgets.']=rewrites['These sizes are proposed budgets.'].replace('6386',str(report['runtime_used_bytes']))
    rewrites['These are ABI 3 build limits.']=rewrites['These sizes are proposed budgets.']
    measured=('The preceding subdivision is the original planning allocation. ABI 3 measured link sizes '
              'are recorded in Appendix B and dist/size-report.json. The compressed runtime consumes ROM '
              f"as well as {report['runtime_used_bytes']} bytes in its {report['runtime_budget_bytes']}-byte "
              'RAM reservation. Gateway code consumes both low-RAM workspace and cartridge space. '
              'The build enforces the 16384-byte cartridge, 768-byte gateway, 6144-byte compiler and 7162-byte runtime limits.')
    rewrites['These are planning allocations, not measured sizes.']=measured
    rewrites['The preceding subdivision is the original planning allocation.']=measured
    rewrites.update({
        'Link the execution image for fixed run addresses': rewrites['Link the execution image for its fixed run addresses'],
        'Link the execution runtime for fixed run addresses': rewrites['Link the execution image for its fixed run addresses'],
        'The implemented allocator has two spans:': rewrites['The allocator therefore has two spans:'],
        'The implemented runtime collector is': rewrites['Runtime string collection may move string payloads'],
        'Bind scalar references during compilation': rewrites['Bind all references during compilation so ordinary scalar accesses'],
        'Fractional constants, E-format constants':
        'Fractional constants, E-format constants, π, SIN, COS, TAN, ATN, EXP, LOG and SQR have no floating-point fallback. RND is implemented as a random 16-bit integer function in revision 0.5.',
        'Preserve BASIC V2 precedence and evaluation order':
        'Preserve eager integer evaluation and BASIC precedence with shifts inserted below addition and above comparisons. Highest to lowest: power (left associative), unary +/- , multiplication/division, addition/subtraction, << and >> (left associative), comparisons, NOT, AND, OR. Relational results are -1 or 0. Shift counts are checked unsigned bytes 0..255. Left shifts wrap the word; arithmetic right shifts repeat its sign bit. Counts of 16 or more produce zero or sign fill. Numeric/string mixing requires explicit conversion; string comparisons use unsigned PETSCII order then length.',
        'Every native body ends physically':
        'Every native body ends physically with its patchable successor JMP. IF ... THEN ... ELSE selects one colon-separated arm for the remainder of its physical line. ELSE binds to the nearest unmatched IF; either arm can be a literal line target. A false IF without ELSE reaches the trailer. Nested IF depth is bounded to 32 and per-line IF patches to 64; a bound failure retains source with a FORMULA TOO COMPLEX stub.',
        'Retain malformed and unsupported source in defined tokens':
        'Retain malformed and unsupported source in defined tokens so it can be LISTed and repaired. Numbered submission reports lexical/assembly failure immediately, while saving tokens and a deferred runtime error stub; successful submission and deletion resume input without READY. An enclosing false IF still skips its malformed unchosen body. Resource failure retains the previous source/code payload.',
        'READY runs the editor/compiler in the command map':
        'READY runs the editor/compiler in the command map. Send the screen-editor carriage return returned by CHRIN to CHROUT before parsing every submitted command, numbered line, deletion or blank line. This advances the cursor before subsequent output or input. Successful numbered entry/deletion resumes input without another READY prompt. Recoverable lexical/assembly failure prints an error but saves the new line. Direct LIST starts on a new line and accepts LIST n, LIST low-high and open endpoints; bounds are inclusive unsigned line numbers 0..63999 and reversed bounds give an empty listing. Direct CLEAN rebuilds dense slabs/symbols, clears variables and invalidates CONT. Other direct statements compile into a transient native payload and synthetic anchor, execute through the RAM gateway and end at DIRECT_DONE.',
    })
    rewrites['Audit zero-page ownership for every supported KERNAL operation.'] = (
        'Audit zero-page ownership for every supported KERNAL operation. Save overlapping language '
        'temporaries or avoid the locations. Place indirect-JMP pointers away from a low byte of $FF '
        'to avoid the NMOS page-boundary bug. RESERVE address,bytes is an implemented compile-time '
        'declaration outside IF: both unsigned numeric literals must be multiples of 256, with a '
        'nonzero range wholly inside a free portion of one user-arena span. Declare up to eight '
        'regions before allocating the program, normally on its first numbered line. Allocation '
        'and collection exclude the full region, with bounds stored outside user RAM. RUN, CLR, '
        'edits and CLEAN preserve reservations; NEW releases them. SAVE/LOAD retain numbered '
        'declarations. Identical bounds are idempotent; occupied/overlapping bounds fail safely. '
        'Removing source or a failed import may leave a reservation until NEW. $C000 is not implicit '
        'scratch RAM, and stock BASIC memory-top POKEs at 55/56 do not configure this allocator.')
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
    def set_cell(cell, text):
        nodes=list(cell.iter(f'{{{W}}}t'))
        nodes[0].text=text
        for node in nodes[1:]:node.text=''
    for table in root.findall('.//w:tbl',NS):
        for row in list(table.findall('w:tr',NS)):
            cells=row.findall('w:tc',NS)
            values=[''.join(c.itertext()) for c in cells]
            if values[0]=='$1400-$7FFF':
                for c,text in zip(cells,('$1400-$2BFF','6 KB','Resident compiler, decompressed at cold start; excluded from user allocation.')):set_cell(c,text)
                new=copy.deepcopy(row)
                for c,text in zip(new.findall('w:tc',NS),('$2C00-$7FFF','21 KB','Common user arena; stable anchors, names and bindings allocate here.')):set_cell(c,text)
                table.insert(list(table).index(row)+1,new)
            elif values[0]=='$1A-$1F':
                for c,text in zip(cells,('$1A-$1B','Arithmetic shift operators << and >>','1 byte')):set_cell(c,text)
                new=copy.deepcopy(row)
                for c,text in zip(new.findall('w:tc',NS),('$1C-$1F','Reserved; reject in format version 1','No valid encoding')):set_cell(c,text)
                table.insert(list(table).index(row)+1,new)
            elif values[0] in ('$20-$67', '$20-$69'):set_cell(cells[0],'$20-$6A')
            elif values[0] in ('$68-$6F', '$6A-$6F'):set_cell(cells[0],'$6B-$6F')
        rows=table.findall('w:tr',NS)
        header=''.join(rows[0].itertext())
        contents=''.join(table.itertext())
        if 'Punctuation or operator' in header and '$1A' not in contents:
            new=copy.deepcopy(rows[-1])
            for c,text in zip(new.findall('w:tc',NS),('$1A','<<','$1B','>>')):set_cell(c,text)
            table.append(new)
        if header=='CodeKeywordCodeKeyword' and '$68' not in contents:
            new=copy.deepcopy(rows[-1])
            for c,text in zip(new.findall('w:tc',NS),('$68','ELSE','$69','CLEAN')):set_cell(c,text)
            table.append(new)
        if header=='CodeKeywordCodeKeyword' and 'RESERVE' not in contents:
            new=copy.deepcopy(rows[-1])
            for c,text in zip(new.findall('w:tc',NS),('$6A','RESERVE','','')):set_cell(c,text)
            table.append(new)
    for row in root.findall('.//w:tr',NS):
        cells=row.findall('w:tc',NS)
        if len(cells)<2:continue
        address=''.join(n.text or '' for n in cells[0].iter(f'{{{W}}}t'))
        if address=='$E000-$E3FF':
            ts=list(cells[1].iter(f'{{{W}}}t'));ts[0].text='1 KB RAM'
            for t in ts[1:]:t.text=''
    marker='Appendix B — implementation status, revision 0.5'
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
        paragraph('Source/container version 1 and runtime ABI 3 are distinct. '
                  'Language zero page is $02-$78; common workspace is $0800-$13FF. '
                  'Function activations currently use a guarded hardware stack with depth eight. '
                  'The compiler emits native helper calls and branches, with literal power-of-two multiplication/division lowered to dedicated arithmetic shift helpers. Division applies a negative-operand bias to preserve truncation toward zero. General inline scalar optimizations remain pending. The compiler reservation is $1400-$2BFF and the arena begins at $2C00.')]
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
                    if n.tag.endswith('}revision'):n.text='5'
                    if n.tag.endswith('}modified'):n.text='2026-10-09T00:00:00Z'
                data=serialize(core,core_namespaces)
            z.writestr(info,data)
    with zipfile.ZipFile(temporary) as z:
        assert z.testzip() is None
        for name in z.namelist():
            if name.endswith('.xml'):ET.fromstring(z.read(name))
    assert hashlib.sha256(DOC.read_bytes()).hexdigest()==design_before, 'Design document changed during synchronization; preserve the user edit and rerun'
    temporary.replace(DOC)
    text='\n'.join(''.join(n.text or '' for n in p.iter(f'{{{W}}}t'))
                   for p in root.iter(f'{{{W}}}p'))+'\n'
    (ROOT/'docs/Assembly_BASIC_C64_Design.txt').write_text(text)
    (ROOT/'docs/design-sync.json').write_text(json.dumps({
        'design_revision':'0.5','runtime_abi':report['runtime_abi'],
        'design_sha256':hashlib.sha256(DOC.read_bytes()).hexdigest(),
        'rom_sha256':report['rom_sha256'],'runtime_run_address':report['runtime_run_address'],
        'arena_raw_bytes':report['arena_raw_bytes'],
        'compiler_run_address':report['compiler_run_address'],
        'compiler_budget_bytes':report['compiler_budget_bytes']},indent=2)+'\n')
    print('Updated design revision 0.5 and readable export; original revision remains in Git.')

if __name__=='__main__':synchronize()
