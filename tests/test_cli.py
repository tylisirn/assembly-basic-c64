import contextlib
import io
from pathlib import Path
import tempfile
import unittest
from ab64.cli import main

class CLITests(unittest.TestCase):
    def test_native_run_exit_status_does_not_mistake_output_for_error(self):
        with tempfile.TemporaryDirectory() as folder:
            program=Path(folder)/'program.bas'
            program.write_text('10 PRINT "?HELLO"\n',encoding='latin-1')
            output=io.StringIO()
            with contextlib.redirect_stdout(output):status=main(['run',str(program)])
            self.assertEqual(status,0)
            self.assertIn('?HELLO',output.getvalue())
            program.write_text('10 PRINT 1/0\n',encoding='latin-1')
            output=io.StringIO()
            with contextlib.redirect_stdout(output):status=main(['run',str(program)])
            self.assertEqual(status,1)
            self.assertIn('?DIVISION BY ZERO',output.getvalue())
