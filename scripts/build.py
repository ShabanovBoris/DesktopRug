#!/usr/bin/env python3
"""Build a native .app using Apple's SDK, Swift compiler and the system Metal compiler."""
from pathlib import Path
import os
import plistlib
import shutil
import struct
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
version = (root / 'VERSION').read_text().strip()
destination = root / 'build' / 'Desktop Rug.app'
contents = destination / 'Contents'
binary = contents / 'MacOS' / 'DesktopRug'
resources = contents / 'Resources'
binary.parent.mkdir(parents=True, exist_ok=True)
resources.mkdir(parents=True, exist_ok=True)
sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
machine = subprocess.check_output(['uname', '-m'], text=True).strip()
target = ('arm64' if machine == 'arm64' else 'x86_64') + '-apple-macosx14.0'
module_cache = root / 'build' / 'ModuleCache'
module_cache.mkdir(exist_ok=True)
sources = sorted(str(p) for p in (root / 'DesktopRug').rglob('*.swift'))
command = ['xcrun', 'swiftc', '-O', '-whole-module-optimization', '-parse-as-library', '-swift-version', '5', '-target', target, '-sdk', sdk, '-module-cache-path', str(module_cache), '-module-name', 'DesktopRug', *sources, '-o', str(binary)]
print('Compiling native Swift application…', flush=True)
subprocess.run(command, check=True, cwd=root / 'build')
for name in ['heriz.png', 'indigo.png', 'soviet-red.png', 'soviet-floral.png']:
    shutil.copy2(root / 'DesktopRug' / 'Resources' / name, resources / name)
shutil.copy2(root / 'LICENSE', resources / 'LICENSE')
shutil.copy2(root / 'DesktopRug/Resources/TextureSources.md', resources / 'TextureSources.md')
shutil.copy2(root / 'DesktopRug' / 'Rendering' / 'RugShaders.metal', resources / 'RugShaders.metal')
icons = root / 'DesktopRug/Resources/Assets.xcassets/AppIcon.appiconset'
elements = []
for icon_type, filename in [('icp4', 'icon_16x16.png'), ('icp5', 'icon_32x32.png'), ('icp6', 'icon_32x32@2x.png'), ('ic07', 'icon_128x128.png'), ('ic08', 'icon_256x256.png'), ('ic09', 'icon_512x512.png'), ('ic10', 'icon_512x512@2x.png')]:
    data = (icons / filename).read_bytes()
    elements.append(icon_type.encode() + struct.pack('>I', len(data) + 8) + data)
data = b''.join(elements)
(resources / 'AppIcon.icns').write_bytes(b'icns' + struct.pack('>I', len(data) + 8) + data)
info = plistlib.loads((root / 'DesktopRug' / 'Info.plist').read_bytes())
replacements = {'$(EXECUTABLE_NAME)': 'DesktopRug', '$(PRODUCT_BUNDLE_IDENTIFIER)': 'dev.desktoprug.app', '$(MARKETING_VERSION)': version, '$(CURRENT_PROJECT_VERSION)': '1', '$(MACOSX_DEPLOYMENT_TARGET)': '14.0'}
for key, value in info.items():
    if isinstance(value, str):
        info[key] = replacements.get(value, value)
info['CFBundleIconFile'] = 'AppIcon'
(contents / 'Info.plist').write_bytes(plistlib.dumps(info, sort_keys=False))
(contents / 'PkgInfo').write_bytes(b'APPL????')
subprocess.run(['codesign', '--force', '--sign', '-', '--options', 'runtime', '--entitlements', str(root / 'DesktopRug/DesktopRug.entitlements'), str(destination)], check=True)
print(f'Built: {destination}')
