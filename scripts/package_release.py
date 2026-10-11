#!/usr/bin/env python3
"""Package and verify the built macOS application, then write its SHA-256."""
from pathlib import Path
import hashlib
import os
import plistlib
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
version = (root / 'VERSION').read_text().strip()
if not re.fullmatch(r'\d+\.\d+\.\d+', version):
    raise SystemExit('VERSION must contain a three-part release version.')
app = root / 'build/Desktop Rug.app'
binary = app / 'Contents/MacOS/DesktopRug'
if not binary.is_file():
    raise SystemExit('Run python3 scripts/build.py before packaging.')
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
if info['CFBundleShortVersionString'] != version:
    raise SystemExit('The built application version differs from VERSION. Rebuild first.')
architectures = subprocess.check_output(['lipo', '-archs', str(binary)], text=True).split()
if architectures == ['arm64']:
    architecture = 'arm64'
elif architectures == ['x86_64']:
    architecture = 'x86_64'
elif set(architectures) == {'arm64', 'x86_64'}:
    architecture = 'universal'
else:
    raise SystemExit(f'Unsupported binary architectures: {architectures}')
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
output = root / 'build/release'
output.mkdir(parents=True, exist_ok=True)
archive = output / f'DesktopRug-v{version}-macOS-{architecture}.zip'
subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(app), str(archive)], check=True)
with tempfile.TemporaryDirectory(prefix='release-check-', dir=root / 'build') as directory:
    subprocess.run(['ditto', '-x', '-k', str(archive), directory], check=True)
    extracted = Path(directory) / app.name
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(extracted)], check=True)
    extracted_binary = extracted / 'Contents/MacOS/DesktopRug'
    if not os.access(extracted_binary, os.X_OK):
        raise SystemExit('The archived executable lost its executable permission.')
    for original in sorted(p for p in app.rglob('*') if p.is_file()):
        restored = extracted / original.relative_to(app)
        if not restored.is_file() or hashlib.sha256(restored.read_bytes()).digest() != hashlib.sha256(original.read_bytes()).digest():
            raise SystemExit(f'Archive verification failed for {original.relative_to(app)}')
    for name in ['LICENSE', 'TextureSources.md', 'heriz.png', 'indigo.png', 'soviet-red.png', 'soviet-floral.png']:
        if not (extracted / 'Contents/Resources' / name).is_file():
            raise SystemExit(f'Missing release resource: {name}')
digest = hashlib.sha256(archive.read_bytes()).hexdigest()
checksum = output / f'{archive.name}.sha256'
checksum.write_text(f'{digest}  {archive.name}\n')
print(f'Verified release: {archive}')
print(f'SHA-256: {digest}')
print(f'Checksum file: {checksum}')
