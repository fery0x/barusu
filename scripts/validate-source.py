#!/usr/bin/env python3
"""Offline checks for syntax, required Niri includes and removed launch commands."""
import json
from pathlib import Path
import re
import subprocess
import tomllib
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parent.parent
checked = 0
for path in root.rglob('*'):
    if not path.is_file() or '.git' in path.parts or '__pycache__' in path.parts:
        continue
    if path.suffix == '.json':
        json.loads(path.read_text())
    elif path.suffix == '.toml':
        tomllib.loads(path.read_text())
    elif path.suffix == '.svg':
        ET.parse(path)
    elif path.suffix == '.py':
        compile(path.read_text(), str(path), 'exec')
    else:
        first = path.read_bytes().split(b'\n', 1)[0]
        if first.startswith(b'#!') and any(shell in first for shell in [b'bash', b'/sh']):
            subprocess.run(['bash', '-n', str(path)], check=True)
    checked += 1

image = root / 'mkosi.extra'
for path in image.rglob('*.kdl'):
    content = path.read_text()
    for optional, target in re.findall(r'^include\s+(optional=true\s+)?"([^"]+)"', content, re.M):
        if optional:
            continue
        resolved = image / target.lstrip('/') if target.startswith('/') else path.parent / target
        assert resolved.is_file(), f'{path}: missing include {target}'
    assert not re.search(r'spawn(?:-sh)?\s+"(?:nautilus|zocr|foot|satty|zjust)\b', content), path

required = {'niri', 'dms', 'dms-cli', 'dms-greeter', 'quickshell', 'greetd', 'ghostty', 'flatpak', 'podman', 'bootc', 'matugen', 'chezmoi', 'just', 'gum'}
removed = {'foot', 'nautilus', 'cava', 'satty', 'tesseract', 'uupd', 'distrobox', 'tailscale', 'valent'}
packages = set()
for path in root.rglob('*.conf'):
    field = ''
    for line in path.read_text().splitlines():
        if line.startswith('['):
            field = ''
        elif line and not line.startswith((' ', '#')) and '=' in line:
            field, value = line.split('=', 1)
            if field == 'Packages':
                packages.update(value.split())
        elif field == 'Packages' and line.startswith(' ') and not line.lstrip().startswith('#'):
            packages.update(line.split())
assert required <= packages, f'Missing explicit packages: {required - packages}'
assert not removed & packages, f'Removed applications are still explicitly selected: {removed & packages}'
assert not {'@standard', '@base-graphical'} & packages
assert not list(image.glob('usr/share/flatpak/preinstall.d/*'))
assert 'bootc update --quiet' in (root / 'mkosi.profiles/bootc-ostree/mkosi.extra/usr/lib/systemd/system/bootc-fetch-apply-updates.service.d/10-stage-only.conf').read_text()
# Chezmoi must own the active user defaults; the retired initializer must not ship.
source = image / 'usr/share/barusu/zdots'
assert (source / '.chezmoiignore').read_text().splitlines() == ['system', 'LICENSE']
assert (source / 'dot_config/ghostty/config').is_file()
assert not (image / 'usr/libexec/barusu-user-defaults').exists()
presets = (image / 'usr/lib/systemd/user-preset/01-barusu.preset').read_text()
assert 'enable chezmoi-init.service' in presets and 'enable chezmoi-update.timer' in presets
for name in ['chezmoi-init.service', 'chezmoi-update.service']:
    assert '/usr/share/barusu/zdots' in (image / 'usr/lib/systemd/user' / name).read_text()
for line in (image / 'usr/lib/tmpfiles.d/99-dms-greeter.conf').read_text().splitlines():
    assert (image / line.split()[-1].lstrip('/')).is_file(), line
assert (image / 'usr/bin/bjust').stat().st_mode & 0o111
assert '/usr/share/barusu/just/00-system.just' in (image / 'usr/bin/bjust').read_text()
assert 'Hostname=barusu' in (root / 'mkosi.conf').read_text()
print(f'PASS: {checked} files; syntax, mandatory Niri includes, package selection and native update configuration')
print('Image build, RPM dependency resolution and desktop/boot smoke tests still require Fedora tooling.')
