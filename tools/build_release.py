"""Baut das Release-ZIP für CurseForge lokal (der GitHub-Workflow nutzt stattdessen den BigWigs-Packager).

Aufruf: python -I tools/build_release.py "<Addon-Ordner>"
Ergebnis: <Addon-Ordner>/dev/dist/SpellRankUp-<Version>.zip mit dem Ordner SpellRankUp/.
Nimmt nur, was die .toc lädt, plus LICENSE.md, README.md und CHANGELOG.md.
Bricht ab, wenn Wörter aus dev/private.txt (eigene Namen, Pfade) in den Dateien stehen.
"""
import os, re, sys, zipfile

A = sys.argv[1]
NAME = 'SpellRankUp'
toc = open(os.path.join(A, NAME + '.toc'), encoding='utf8').read()
version = re.search(r'^## Version:\s*(\S+)', toc, re.M).group(1)
if version.startswith('@'):  # Platzhalter für den Packager: lokal die Version aus dem letzten Git-Tag nehmen
    import subprocess
    try:
        version = subprocess.run(['git', '-C', A, 'describe', '--tags', '--always'], capture_output=True, text=True, check=True).stdout.strip()
    except Exception:
        version = 'dev'
    toc = toc.replace('@project-version@', version)
files = [l.strip() for l in toc.splitlines() if l.strip() and not l.startswith('#')]
EXTRA = ['LICENSE.md', 'README.md', 'CHANGELOG.md']

# Schutz: keine eigenen Daten oder Entwicklungsdateien im Paket
words = ['AppData', 'scratchpad', 'WTF/Account', 'WTF\\\\Account']
private_list = os.path.join(A, 'dev', 'private.txt')
if os.path.isfile(private_list):
    words += [w.strip() for w in open(private_list, encoding='utf8') if w.strip()]
private = re.compile('|'.join(re.escape(w) for w in words), re.I)
problems = []
for f in files + EXTRA:
    path = os.path.join(A, f)
    if not os.path.isfile(path): problems.append('fehlt: ' + f)
    elif private.search(open(path, encoding='utf8').read()): problems.append('private Daten in ' + f)
if problems:
    sys.exit('Abbruch:\n  ' + '\n  '.join(problems))

out_dir = os.path.join(A, 'dev', 'dist')
os.makedirs(out_dir, exist_ok=True)
out = os.path.join(out_dir, f'{NAME}-{version}.zip')
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    z.writestr(f'{NAME}/{NAME}.toc', toc)
    for f in files + EXTRA:
        z.write(os.path.join(A, f), f'{NAME}/{f}')
with zipfile.ZipFile(out) as z:
    for i in z.infolist(): print(f'{i.file_size:>9}  {i.filename}')
print('\n' + out, os.path.getsize(out), 'Bytes')
