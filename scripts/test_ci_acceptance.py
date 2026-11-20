"""The runner gate must fail on lost driver output, while exercising both flavors."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class AcceptanceGateTest(unittest.TestCase):
    def run_gate(self, mode):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'scripts').mkdir()
            (root / 'bin').mkdir()
            shutil.copy(Path(__file__).with_name('jarvis_ci_acceptance.sh'), root / 'scripts')
            (root / 'scripts/unified_acceptance.sh').write_text('#!/bin/sh\nexit 0\n')
            (root / 'bin/adb').write_text('#!/bin/sh\nexit 0\n')
            (root / 'bin/flutter').write_text('''#!/usr/bin/env python3
import os, sys
flavor = sys.argv[sys.argv.index('--flavor') + 1]
with open('flavors.txt', 'a') as f: f.write(flavor + '\\n')
mode = os.environ['GATE_TEST_MODE']
for n in range(1, 14):
    if mode == 'missing' and flavor == 'full' and n == 13: continue
    print(f'ACCEPT I{n:02d} PASS simulated')
print('All tests passed!')
if mode == 'driver_failure' and flavor == 'standard': sys.exit(42)
if mode == 'reported_failure' and flavor == 'full': print('ACCEPT I13 FAIL simulated')
''')
            for executable in (root / 'bin').iterdir(): executable.chmod(0o755)
            env = {**os.environ, 'PATH': str(root / 'bin') + os.pathsep + os.environ['PATH'],
                   'GATE_TEST_MODE': mode}
            result = subprocess.run(['bash', 'scripts/jarvis_ci_acceptance.sh', 'evidence'],
                                    cwd=root, env=env, capture_output=True, text=True)
            self.assertEqual((root / 'flavors.txt').read_text().splitlines(), ['standard', 'full'])
            return result.returncode

    def test_complete_evidence_passes(self): self.assertEqual(self.run_gate('ok'), 0)
    def test_driver_exit_survives_tee(self): self.assertNotEqual(self.run_gate('driver_failure'), 0)
    def test_missing_full_evidence_fails(self): self.assertNotEqual(self.run_gate('missing'), 0)
    def test_reported_failure_fails_even_after_pass_line(self):
        self.assertNotEqual(self.run_gate('reported_failure'), 0)


if __name__ == '__main__': unittest.main()
