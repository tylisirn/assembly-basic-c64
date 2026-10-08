#!/usr/bin/env python3
"""Run source and native CPU tests against the current built cartridge."""
from pathlib import Path
import sys
import unittest
import hashlib
import json
ROOT=Path(__file__).resolve().parents[1]
for p in ('host','tests','.tools/py65'):sys.path.insert(0,str(ROOT/p))
from check_runtime import check
instructions=check()
suite=unittest.defaultTestLoader.discover(str(ROOT/'tests'))
result=unittest.TextTestRunner(verbosity=2).run(suite)
(ROOT/'build/test-report.json').write_text(json.dumps({
    'tests_run':result.testsRun,'failures':len(result.failures),
    'errors':len(result.errors),'skipped':len(result.skipped),
    'runtime_instructions_checked':instructions,
    'rom_sha256':hashlib.sha256((ROOT/'build/assembly-basic.bin').read_bytes()).hexdigest(),
    'environment':'instruction-level py65, deterministic KERNAL stubs'
},indent=2)+'\n')
raise SystemExit(0 if result.wasSuccessful() else 1)
