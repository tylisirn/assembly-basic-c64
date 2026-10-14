"""Check that source notation becomes editable Word structure without data loss."""
from pathlib import Path
import sys
import unittest
import xml.etree.ElementTree as ET

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from design_formatting import W, REL, NS, WordContent, export_text, text_of


class DesignFormattingTests(unittest.TestCase):
    def word(self):
        return WordContent(ET.Element(f'{{{REL}}}Relationships'),
                           ET.Element(f'{{{W}}}numbering'), 9936)

    def test_tables_links_and_inline_notation_become_word_content(self):
        source = ('# Title\n\n**Bold** and `A%` and \\(w < 32768\\).\n\n'
                  '| Key | Meaning |\n|---|---|\n| `A%` | Unsigned |\n\n'
                  '[This section](#title) and [data](measurements.json).')
        word = self.word()
        word.prepare_sources([('sample.md', source)])
        nodes = word.markdown(source, 'sample.md')
        root = ET.Element('root')
        root.extend(nodes)
        table = root.find('w:tbl', NS)
        self.assertEqual(len(table.findall('w:tr', NS)), 2)
        self.assertEqual(text_of(table), 'KeyMeaningA%Unsigned')
        self.assertIsNotNone(table.find('w:tr/w:trPr/w:tblHeader', NS))
        self.assertIn('Bold and A% and w < 32768.', text_of(root))
        self.assertIsNotNone(root.find('.//w:rPr/w:b', NS))
        self.assertIsNotNone(root.find('.//w:rPr/w:i', NS))
        self.assertIsNotNone(root.find('.//w:rPr/w:rFonts', NS))
        links = root.findall('.//w:hyperlink', NS)
        self.assertEqual(links[0].get(f'{{{W}}}anchor'),
                         root.find('.//w:bookmarkStart', NS).get(f'{{{W}}}name'))
        self.assertEqual(word.relationships[0].get('Target'), 'docs/measurements.json')

    def test_literal_code_preserves_indentation_and_operators(self):
        code = '  PRINT A*B:REM **literal**\n\n.byte $00, $ff'
        word = self.word()
        nodes = word.markdown('```basic\n' + code + '\n```', 'sample.md')
        root = ET.Element(f'{{{W}}}document')
        body = ET.SubElement(root, f'{{{W}}}body')
        body.extend(nodes)
        self.assertEqual(export_text(root), code + '\n')
        self.assertEqual(len(nodes), 1)
        self.assertEqual(nodes[0].find('w:pPr/w:pStyle', NS).get(f'{{{W}}}val'), 'AssemblyCode')

    def test_separate_ordered_lists_restart_and_regeneration_reuses_definitions(self):
        source = '1. First\n2. Second\n\nAnother sequence:\n\n1. New first\n2. New second'
        word = self.word()
        nodes = word.markdown(source, 'sample.md')
        ids = [p.find('w:pPr/w:numPr/w:numId', NS).get(f'{{{W}}}val')
               for p in nodes if p.find('w:pPr/w:numPr', NS) is not None]
        self.assertEqual(ids[0], ids[1])
        self.assertEqual(ids[2], ids[3])
        self.assertNotEqual(ids[0], ids[2])
        for num in word.numbering.findall('w:num', NS):
            self.assertEqual(num.find('w:lvlOverride/w:startOverride', NS).get(f'{{{W}}}val'), '1')
        before = ET.tostring(word.numbering)
        word = WordContent(word.relationships, word.numbering, word.width)
        word.markdown(source, 'sample.md')
        self.assertEqual(ET.tostring(word.numbering), before)


if __name__ == '__main__':
    unittest.main()
