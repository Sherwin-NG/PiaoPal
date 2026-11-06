import hashlib
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
VERSION = plistlib.loads((ROOT / 'Info.plist').read_bytes())['CFBundleShortVersionString']
PREFIX = f'PiaoPal-v{VERSION}'
MAC = [f'{PREFIX}-macOS-universal.dmg', f'{PREFIX}-macOS-universal.zip']
WINDOWS = [f'{PREFIX}-Windows-x64.zip', f'{PREFIX}-Windows-arm64.zip']


class ReleaseManifestTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.directory = Path(self.temporary.name)
        self.addCleanup(self.temporary.cleanup)

    def write_packages(self, names):
        for name in names:
            (self.directory / name).write_bytes(f'package bytes for {name}'.encode())

    def run_manifest(self, platform='all', version=VERSION):
        return subprocess.run([
            sys.executable, str(ROOT / 'scripts/release-checksums.py'),
            '--version', version, '--directory', str(self.directory), '--platform', platform,
        ], capture_output=True, text=True)

    def test_cross_platform_release_requires_both_windows_architectures(self):
        self.write_packages(MAC + WINDOWS[:1])
        result = self.run_manifest()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Windows-arm64.zip', result.stderr)
        self.assertFalse((self.directory / 'SHA256SUMS.txt').exists())

    def test_complete_release_hashes_exactly_four_packages(self):
        self.write_packages(MAC + WINDOWS)
        (self.directory / 'unrelated.zip').write_bytes(b'not a release asset')
        result = self.run_manifest()
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = (self.directory / 'SHA256SUMS.txt').read_text().splitlines()
        self.assertEqual(len(lines), 4)
        for line, name in zip(lines, sorted(MAC + WINDOWS)):
            self.assertEqual(line, f'{hashlib.sha256((self.directory / name).read_bytes()).hexdigest()}  {name}')

    def test_macos_job_remains_independent(self):
        self.write_packages(MAC)
        result = self.run_manifest('macos')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len((self.directory / 'SHA256SUMS.txt').read_text().splitlines()), 2)

    def test_empty_package_cannot_publish_manifest(self):
        self.write_packages(MAC + WINDOWS)
        (self.directory / WINDOWS[0]).write_bytes(b'')
        self.assertNotEqual(self.run_manifest().returncode, 0)
        self.assertFalse((self.directory / 'SHA256SUMS.txt').exists())

    def test_rejects_version_mismatch(self):
        self.assertNotEqual(self.run_manifest(version='999.0.0').returncode, 0)


if __name__ == '__main__':
    unittest.main()
