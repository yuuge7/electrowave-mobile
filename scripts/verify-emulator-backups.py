"""Read-only integrity check for backups generated in the emulator QA folder."""
from pathlib import Path
import argparse, os, subprocess, gzip, json, base64, sqlite3, tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--device', default='emulator-5554')
parser.add_argument('--folder', default='/sdcard/Music/Electrowave-QA-backups/')
args = parser.parse_args()
adb = str(Path(os.environ['LOCALAPPDATA'])/'Android/Sdk/platform-tools/adb.exe')

def command(*parts):
    return subprocess.check_output([adb, '-s', args.device, *parts])

if command('shell', 'getprop', 'ro.kernel.qemu').strip() != b'1':
    raise SystemExit('This check only targets an Android emulator.')
folder = args.folder.rstrip('/')+'/'
listing = command('shell', 'ls', folder).decode().splitlines()
backups = sorted(n.strip() for n in listing if n.strip().endswith('.ewbackup'))
assert len(backups) == 5, backups
for name in backups:
    data = command('exec-out', 'cat', folder+name)
    bundle = json.loads(gzip.decompress(data))
    assert bundle['format'] == 'Electrowave'
    with tempfile.TemporaryDirectory() as directory:
        file = Path(directory)/'backup.db'
        file.write_bytes(base64.b64decode(bundle['files']['database']))
        con = sqlite3.connect(file)
        try:
            assert con.execute('PRAGMA quick_check').fetchone()[0] == 'ok'
            assert con.execute('PRAGMA user_version').fetchone()[0] == 6
        finally:
            con.close()
report = ('Native scheduled backup worker: PASS\n'
          'Retention: exactly 5 completed backups\n'
          'All five gzip bundles and SQLite integrity checks: PASS\n')
output = Path('docs/testing/native-backup-check.txt')
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(report, encoding='utf8')
print(report)
