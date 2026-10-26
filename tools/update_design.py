#!/usr/bin/env python3
"""Generate the design DOCX/text from current Markdown and matched build facts."""
from pathlib import Path
import copy
import hashlib
import io
import json
import xml.etree.ElementTree as ET
import zipfile
from design_formatting import WordContent, build_tables, export_text

ROOT = Path(__file__).resolve().parents[1]
DESIGN = ROOT / 'docs/design'
IMPLEMENTATION = ROOT / 'docs/implementation'
DOC = DESIGN / 'Assembly_BASIC_C64_Design.docx'
SOURCES = ('architecture.md', 'banking.md', 'integer_arithmetic.md',
           'source_format.md', 'editors.md')
W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
NS = {'w': W}
ET.register_namespace('w', W)


def namespaces(data):
    result = dict(value for _, value in ET.iterparse(io.BytesIO(data), events=['start-ns']))
    for prefix, uri in result.items():
        ET.register_namespace(prefix, uri)
    return result


def serialize(root, declared):
    data = ET.tostring(root, encoding='utf-8', xml_declaration=True)
    # Preserve unused declarations, including prefixes named by mc:Ignorable.
    extras = ''.join(f' xmlns:{prefix}="{uri}"' for prefix, uri in declared.items()
                     if prefix and f'xmlns:{prefix}='.encode() not in data)
    end = data.index(b'>', data.index(b'?>') + 2)
    return data[:end] + extras.encode() + data[end:]


def synchronize():
    report = json.loads((ROOT / 'build/size-report.json').read_text())
    tests = json.loads((ROOT / 'build/test-report.json').read_text())
    assert tests['failures'] == tests['errors'] == 0, 'Fix test failures before generating the design'
    assert tests['rom_sha256'] == report['rom_sha256'], 'Tests refer to a different cartridge build'
    source_bytes = [(name, (DESIGN / name).read_bytes()) for name in SOURCES]
    sources = [(name, data.decode('utf-8')) for name, data in source_bytes]
    source_hashes = {name: hashlib.sha256(data).hexdigest()
                     for name, data in source_bytes}
    design_before = hashlib.sha256(DOC.read_bytes()).hexdigest()
    with zipfile.ZipFile(DOC) as archive:
        entries = [(info, archive.read(info.filename)) for info in archive.infolist()]
    parts = {info.filename: data for info, data in entries}
    declared = namespaces(parts['word/document.xml'])
    root = ET.fromstring(parts['word/document.xml'])
    body = root.find('w:body', NS)
    section = copy.deepcopy(body.find('w:sectPr', NS))
    relationships = ET.fromstring(parts['word/_rels/document.xml.rels'])
    for relationship in list(relationships):
        if relationship.get('Type', '').endswith('/hyperlink'):
            relationships.remove(relationship)
    numbering = ET.fromstring(parts['word/numbering.xml'])
    page = section.find('w:pgSz', NS)
    margins = section.find('w:pgMar', NS)
    width = int(page.get(f'{{{W}}}w')) - sum(
        int(margins.get(f'{{{W}}}{side}')) for side in ('left', 'right', 'gutter'))
    word = WordContent(relationships, numbering, width)
    word.prepare_sources(sources)
    # The Markdown files are authoritative. Rebuild the body so obsolete prose
    # cannot survive as an untouched original section or historical appendix.
    body.clear()
    body.append(word.heading('Assembly BASIC for the Commodore 64', 1))
    body.append(word.paragraph('Current architecture and format specifications. '
                               'Generated from docs/design Markdown; edit those sources. '
                               'Build tables identify the measured ROM. Validation gaps '
                               'are recorded separately in docs/implementation/STATUS.md.'))
    for name, text in sources:
        body.extend(word.markdown(text, name))
    body.extend(build_tables(word, report))
    body.append(section)
    temporary = DOC.with_suffix('.docx.tmp')
    with zipfile.ZipFile(temporary, 'w') as archive:
        for info, data in entries:
            if info.filename == 'word/document.xml':
                data = serialize(root, declared)
            elif info.filename == 'word/_rels/document.xml.rels':
                data = serialize(relationships, namespaces(data))
            elif info.filename == 'word/numbering.xml':
                data = serialize(numbering, namespaces(data))
            elif info.filename == 'docProps/core.xml':
                core_namespaces = namespaces(data)
                core = ET.fromstring(data)
                # Historical release labels do not describe the generated design.
                for node in list(core):
                    if node.tag.endswith('}revision') or node.tag.endswith('}modified'):
                        core.remove(node)
                data = serialize(core, core_namespaces)
            archive.writestr(info, data)
    with zipfile.ZipFile(temporary) as archive:
        assert archive.testzip() is None
        for name in archive.namelist():
            if name.endswith('.xml'):
                ET.fromstring(archive.read(name))
    assert hashlib.sha256(DOC.read_bytes()).hexdigest() == design_before, (
        'Design document changed during generation; preserve the user edit and rerun')
    temporary.replace(DOC)
    (DESIGN / 'Assembly_BASIC_C64_Design.txt').write_text(
        export_text(root).rstrip('\n') + '\n', encoding='utf-8')
    (IMPLEMENTATION / 'design-sync.json').write_text(json.dumps({
        'runtime_abi': report['runtime_abi'],
        'design_sha256': hashlib.sha256(DOC.read_bytes()).hexdigest(),
        'source_sha256': source_hashes,
        'rom_sha256': report['rom_sha256'],
        'runtime_run_address': report['runtime_run_address'],
        'arena_raw_bytes': report['arena_raw_bytes'],
        'compiler_run_address': report['compiler_run_address'],
        'compiler_budget_bytes': report['compiler_budget_bytes'],
    }, indent=2) + '\n', encoding='utf-8')
    print('Updated current design DOCX, text export and source fingerprints.')


if __name__ == '__main__':
    synchronize()
