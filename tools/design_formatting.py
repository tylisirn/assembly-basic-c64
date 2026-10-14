"""Render the design's Markdown sources and measurements as native Word content.

Only the Markdown constructs used by the design sources are supported. The
renderer uses the document's existing styles and adds no third-party dependency.
"""
from pathlib import PurePosixPath
import posixpath
import re
import xml.etree.ElementTree as ET

W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
R = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
REL = 'http://schemas.openxmlformats.org/package/2006/relationships'
NS = {'w': W}


def element(tag, parent=None, **attrs):
    node = ET.Element(f'{{{W}}}{tag}', {f'{{{W}}}{k}': str(v) for k, v in attrs.items()})
    if parent is not None:
        parent.append(node)
    return node


def text_of(node):
    return ''.join(t.text or '' for t in node.iter(f'{{{W}}}t'))


def slug(text):
    return re.sub(r'[^\w -]', '', text.lower()).replace(' ', '-')


class WordContent:
    def __init__(self, relationships, numbering, width):
        self.relationships = relationships
        self.numbering = numbering
        self.width = width
        self.bookmarks = {}
        self.bookmark_id = 1000
        # Reuse our definition on later synchronizations, without accumulating
        # orphaned list instances when Appendix B is replaced.
        owned = {n.get(f'{{{W}}}abstractNumId') for n in numbering
                 if n.find("w:name[@w:val='DesignDecimal']", NS) is not None}
        for node in list(numbering):
            ref = node.find('w:abstractNumId', NS)
            if node.get(f'{{{W}}}abstractNumId') in owned or (
                    ref is not None and ref.get(f'{{{W}}}val') in owned):
                numbering.remove(node)
        ids = [int(n.get(f'{{{W}}}abstractNumId'))
               for n in numbering.findall('w:abstractNum', NS)]
        self.decimal_id = max(ids, default=-1) + 1
        abstract = element('abstractNum', abstractNumId=self.decimal_id)
        element('multiLevelType', abstract, val='singleLevel')
        element('name', abstract, val='DesignDecimal')
        level = element('lvl', abstract, ilvl=0)
        element('start', level, val=1)
        element('numFmt', level, val='decimal')
        element('lvlText', level, val='%1.')
        props = element('pPr', level)
        element('ind', props, left=360, hanging=240)
        first_num = numbering.find('w:num', NS)
        index = list(numbering).index(first_num) if first_num is not None else len(numbering)
        numbering.insert(index, abstract)

    def number_list(self, start):
        ids = [int(n.get(f'{{{W}}}numId')) for n in self.numbering.findall('w:num', NS)]
        num_id = max(ids, default=0) + 1
        num = element('num', self.numbering, numId=num_id)
        element('abstractNumId', num, val=self.decimal_id)
        override = element('lvlOverride', num, ilvl=0)
        element('startOverride', override, val=start)
        return num_id

    def run(self, parent, text, bold=False, code=False, italic=False, link=False):
        if not text:
            return
        run = element('r', parent)
        if bold or code or italic or link:
            props = element('rPr', run)
            if code:
                element('rFonts', props, ascii='Consolas', hAnsi='Consolas')
                element('sz', props, val=18)
            if bold:
                element('b', props)
            if italic:
                element('i', props)
            if link:
                element('color', props, val='0563C1')
                element('u', props, val='single')
        # Word line breaks preserve captured output and multi-line code, while
        # keeping it out of JSON escape syntax.
        for i, line in enumerate(text.replace('\r\n', '\n').replace('\r', '\n').split('\n')):
            if i:
                element('br', run)
            t = element('t', run)
            t.set('{http://www.w3.org/XML/1998/namespace}space', 'preserve')
            t.text = line

    def inline(self, parent, text, source='', bold=False, italic=False, link=False):
        pattern = r'(`[^`\n]+`|\*\*.+?\*\*|\[[^\]]+\]\([^)]+\)|\\\(.+?\\\)|(?<!\w)\*[^*\n]+\*)'
        pos = 0
        for match in re.finditer(pattern, text):
            self.run(parent, text[pos:match.start()], bold=bold, italic=italic, link=link)
            token = match.group()
            if token.startswith('`'):
                self.run(parent, token[1:-1], code=True, bold=bold, link=link)
            elif token.startswith('**'):
                self.inline(parent, token[2:-2], source, bold=True, italic=italic, link=link)
            elif token.startswith('['):
                label, target = re.fullmatch(r'\[([^\]]+)\]\(([^)]+)\)', token).groups()
                path, _, fragment = target.partition('#')
                key = (PurePosixPath(path).name if path else source, fragment)
                hyperlink = element('hyperlink', parent)
                if key in self.bookmarks:
                    hyperlink.set(f'{{{W}}}anchor', self.bookmarks[key])
                else:
                    if not re.match(r'^[a-zA-Z][\w+.-]*:', target):
                        target = posixpath.normpath('docs/' + target)
                    existing = next((r for r in self.relationships
                                     if r.get('Target') == target and
                                     r.get('Type', '').endswith('/hyperlink')), None)
                    if existing is None:
                        used = {r.get('Id') for r in self.relationships}
                        index = 1
                        while f'designLink{index}' in used:
                            index += 1
                        existing = ET.SubElement(self.relationships, f'{{{REL}}}Relationship', {
                            'Id': f'designLink{index}', 'Type': R + '/hyperlink',
                            'Target': target, 'TargetMode': 'External'})
                    hyperlink.set(f'{{{R}}}id', existing.get('Id'))
                self.inline(hyperlink, label, source, bold=bold, italic=italic, link=True)
            elif token.startswith('\\('):
                self.run(parent, token[2:-2], italic=True, bold=bold)
            else:
                self.inline(parent, token[1:-1], source, bold=bold, italic=True, link=link)
            pos = match.end()
        self.run(parent, text[pos:], bold=bold, italic=italic, link=link)

    def paragraph(self, text='', style=None, source='', literal=False, **formatting):
        p = element('p')
        if style:
            props = element('pPr', p)
            element('pStyle', props, val=style)
        if literal:
            self.run(p, text, code=True)
        else:
            self.inline(p, text, source, **formatting)
        return p

    def heading(self, text, level=2, source='', anchor=''):
        p = self.paragraph(text, f'Heading{level}', source)
        if source:
            self.bookmark_id += 1
            name = self.bookmarks[(source, anchor)]
            p.insert(1, element('bookmarkStart', id=self.bookmark_id, name=name))
            element('bookmarkEnd', p, id=self.bookmark_id)
        return p

    def table(self, headers, rows, widths=None, source='', literal=False):
        table = element('tbl')
        props = element('tblPr', table)
        element('tblStyle', props, val='TableGrid')
        element('tblW', props, w=self.width, type='dxa')
        element('tblLayout', props, type='fixed')
        margins = element('tblCellMar', props)
        for side in ['top', 'left', 'bottom', 'right']:
            element(side, margins, w=70, type='dxa')
        widths = widths or [self.width // len(headers)] * len(headers)
        widths[-1] += self.width - sum(widths)
        grid = element('tblGrid', table)
        for width in widths:
            element('gridCol', grid, w=width)
        for row_index, values in enumerate([headers, *rows]):
            assert len(values) == len(headers), (headers, values)
            row = element('tr', table)
            row_props = element('trPr', row)
            element('cantSplit', row_props)
            if row_index == 0:
                element('tblHeader', row_props)
            for value, width in zip(values, widths):
                cell = element('tc', row)
                cell_props = element('tcPr', cell)
                element('tcW', cell_props, w=width, type='dxa')
                if row_index == 0:
                    element('shd', cell_props, fill='E7E6E6')
                element('vAlign', cell_props, val='top')
                p = self.paragraph(str(value), source=source, literal=literal and row_index > 0,
                                   bold=row_index == 0)
                p_props = element('pPr')
                # Keep small comparison/counter tables together. Larger tables
                # break between rows and repeat their header on each page.
                if row_index == 0 or (len(rows) <= 6 and row_index < len(rows)):
                    element('keepNext', p_props)
                element('spacing', p_props, after=40, line=240, lineRule='auto')
                p.insert(0, p_props)
                cell.append(p)
        return table

    def prepare_sources(self, sources):
        """Reserve bookmarks before rendering forward links between source files."""
        for name, text in sources:
            titles = [m.group(2) for line in text.splitlines()
                      if (m := re.match(r'^(#+)\s+(.+)', line))]
            self.bookmarks[(name, '')] = f'DesignSection{len(self.bookmarks)}'
            for title in titles:
                self.bookmarks[(name, slug(title))] = f'DesignSection{len(self.bookmarks)}'

    def markdown(self, text, source):
        lines = text.splitlines()
        levels = [len(m.group(1)) for line in lines if (m := re.match(r'^(#+) ', line))]
        minimum = min(levels, default=1)
        # The integer source uses a bold document title above level-three headings.
        bold_title = bool(lines and re.fullmatch(r'\*\*.+\*\*', lines[0]))
        nodes, pending = [], []
        i = 0
        list_id = None

        def flush():
            if pending:
                nodes.append(self.paragraph(' '.join(pending), source=source))
                pending.clear()

        while i < len(lines):
            line = lines[i].strip()
            heading = re.match(r'^(#+)\s+(.+)', line)
            ordered = re.match(r'^(\d+)\.\s+(.+)', line)
            bullet = re.match(r'^[-*]\s+(.+)', line)
            if not line:
                flush()
                i += 1
                continue
            if line.startswith('```'):
                flush()
                list_id = None
                i += 1
                code = []
                while i < len(lines) and not lines[i].strip().startswith('```'):
                    code.append(lines[i])
                    i += 1
                if i == len(lines):
                    raise ValueError(f'Unclosed code fence in {source}')
                # Keep each short code block together with the explanation
                # immediately following it, without a chain of code paragraphs.
                p = self.paragraph('\n'.join(code), 'AssemblyCode', literal=True)
                props = p.find('w:pPr', NS)
                element('keepLines', props)
                element('spacing', props, before=80, after=120)
                nodes.append(p)
            elif heading or (i == 0 and bold_title):
                flush()
                list_id = None
                title = heading.group(2) if heading else line[2:-2]
                level = (len(heading.group(1)) - minimum + 2 + int(bold_title)) if heading else 2
                anchor = slug(title) if heading else ''
                if not nodes and heading:
                    self.bookmarks[(source, anchor)] = self.bookmarks[(source, '')]
                nodes.append(self.heading(title, min(level, 4), source, anchor))
            elif line.startswith('|') and i + 1 < len(lines) and re.fullmatch(r'[\s|:-]+', lines[i + 1]):
                flush()
                list_id = None
                def fields(value):
                    return [v.strip() for v in value.strip().strip('|').split('|')]
                headers = fields(line)
                i += 2
                rows = []
                while i < len(lines) and lines[i].strip().startswith('|'):
                    rows.append(fields(lines[i]))
                    i += 1
                widths = None
                if headers == ['Area', 'Implemented behavior', 'Remaining work']:
                    widths = [1400, 5050, self.width - 6450]
                elif headers[0] == 'Bank':
                    widths = [650, 3650, 1700, self.width - 6000]
                nodes.append(self.table(headers, rows, widths, source))
                nodes.append(self.paragraph())
                continue
            elif ordered or bullet:
                flush()
                if ordered and list_id is None:
                    list_id = self.number_list(int(ordered.group(1)))
                if bullet:
                    list_id = None
                p = self.paragraph(ordered.group(2) if ordered else bullet.group(1),
                                   'ListNumber' if ordered else 'ListBullet', source)
                props = p.find('w:pPr', NS)
                num = element('numPr', props)
                element('ilvl', num, val=0)
                element('numId', num, val=list_id if ordered else 1)
                nodes.append(p)
            elif re.fullmatch(r'\*\*.+\*\*', line):
                flush()
                list_id = None
                nodes.append(self.heading(line[2:-2], 4, source=''))
            else:
                list_id = None
                pending.append(line)
            i += 1
        flush()
        return nodes


def label(key):
    overrides = {'rom': 'ROM', 'abi': 'ABI', 'cpu': 'CPU', 'sha256': 'SHA-256',
                 'kernal': 'KERNAL', 'crc': 'CRC'}
    value = ' '.join(overrides.get(word, word) for word in key.split('_'))
    return value[0].upper() + value[1:]


def scalar(key, value):
    if isinstance(value, bool):
        return 'Yes' if value else 'No'
    if isinstance(value, int):
        if key.endswith('_address') or key == 'bank_register':
            return f'${value:04X} ({value:,})'
        return f'{value:,}'
    if isinstance(value, list):
        return f'[${value[0]:04X}, ${value[1]:04X}) (exclusive end)'
    # Long fingerprints need discretionary breaks to fit inside a table cell.
    if key == 'rom_sha256':
        return '\u200b'.join(value[i:i + 8] for i in range(0, len(value), 8))
    return str(value)


def build_tables(word, report):
    nodes = [word.heading('Measured linked build')]
    fields = [(label(k), scalar(k, v)) for k, v in report.items()
              if k not in ('banks', 'segments', 'arena_spans')]
    nodes.append(word.table(['Build property', 'Measured value'], fields,
                            [3600, word.width - 3600]))
    nodes.append(word.paragraph())
    nodes.append(word.heading('User arena spans', 3))
    nodes.append(word.table(['Start', 'Exclusive end', 'Raw bytes'], [
        [f'${start:04X}', f'${end:04X}', f'{end - start:,}']
        for start, end in report['arena_spans']]))
    nodes.append(word.paragraph())
    nodes.append(word.heading('Cartridge bank allocation', 3))
    windows = {tuple(b['window']) for b in report['banks']}
    assert len(windows) == 1, 'Bank windows differ; show individual windows in the design'
    start, end = windows.pop()
    nodes.append(word.paragraph(f'Each bank uses the CPU window [${start:04X}, ${end:04X}), '
                                'with an exclusive upper bound. ROM offsets below are byte offsets.'))
    nodes.append(word.table(['Bank', 'ROM offset', 'Contents', 'Used bytes', 'Spare bytes', 'Reserved'], [
        [b['bank'], f"{b['offset']:,}", b['role'], f"{b['used_bytes']:,}",
         f"{b['spare_bytes']:,}", 'Yes' if b['reserved'] else 'No'] for b in report['banks']],
        [600, 1100, word.width - 4900, 1050, 1050, 1100]))
    nodes.append(word.paragraph())
    nodes.append(word.heading('Linked segment sizes', 3))
    nodes.append(word.table(['Segment', 'Bytes'], [(k, f'{v:,}') for k, v in report['segments'].items()]))
    nodes.append(word.paragraph())
    return nodes


def measurement_tables(word, measurements):
    nodes = [word.heading('Instruction-level measurements and capacity scenario')]
    nodes.append(word.table(['Measurement context', 'Value'], [
        [label(k), scalar(k, v)] for k, v in measurements.items()
        if k not in ('workloads', 'capacity_scenario')]))
    nodes.append(word.paragraph())
    for name, workload in measurements['workloads'].items():
        nodes.append(word.heading(label(name), 3))
        nodes.append(word.table(['Counter', 'Instructions'], [
            ['Source entry', f"{workload['entry_instructions']:,}"],
            ['RUN', f"{workload['run_instructions']:,}"]]))
        nodes.append(word.paragraph('Captured output (spaces and line breaks preserved):'))
        nodes.append(word.paragraph(workload['output'], 'AssemblyCode', literal=True))
        nodes.append(word.table(['BASIC line', 'Token bytes', 'Native bytes', 'Physical payload bytes'], [
            [line['line'], line['token_bytes'], line['native_bytes'], line['payload_physical_bytes']]
            for line in workload['lines']]))
        nodes.append(word.paragraph())
    capacity = measurements['capacity_scenario']
    nodes.append(word.heading('Capacity scenario', 3))
    nodes.append(word.table(['Capacity property', 'Value'], [
        [label(k), scalar(k, v)] for k, v in capacity.items() if k != 'failure']))
    nodes.append(word.paragraph('Captured failure output (spaces and line breaks preserved):'))
    nodes.append(word.paragraph(capacity['failure'], 'AssemblyCode', literal=True))
    return nodes


def collection_tables(word, collection):
    nodes = [word.heading('Captured Void Runner collection replay')]
    nodes.append(word.table(['Replay property', 'Value'], [
        [label(k), scalar(k, v)] for k, v in collection.items()]))
    nodes.append(word.paragraph())
    return nodes


def export_text(root):
    """Keep tables, captured line breaks and paragraph order in the text export."""
    def paragraph_text(p):
        return ''.join((n.text or '') if n.tag == f'{{{W}}}t' else
                       '\n' if n.tag == f'{{{W}}}br' else
                       '\t' if n.tag == f'{{{W}}}tab' else '' for n in p.iter())
    lines = []
    for node in root.find('w:body', NS):
        if node.tag == f'{{{W}}}p':
            lines.append(paragraph_text(node))
        elif node.tag == f'{{{W}}}tbl':
            for row in node.findall('w:tr', NS):
                lines.append('\t'.join('\n'.join(paragraph_text(p) for p in cell.findall('w:p', NS))
                                       for cell in row.findall('w:tc', NS)))
    return '\n'.join(line.rstrip() for line in '\n'.join(lines).replace('\u200b', '').split('\n')) + '\n'
