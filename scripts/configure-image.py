#!/usr/bin/env python3
"""Set the GitHub image identity and public verification key before publishing."""
import argparse
import json
from pathlib import Path
import re

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('repository', help='GitHub OWNER/REPOSITORY, matching the fork')
parser.add_argument('--public-key', type=Path, help='Public cosign PEM key matching SIGNING_SECRET')
parser.add_argument('--check', action='store_true', help='Verify the current configuration without modifying it')
args = parser.parse_args()
repo = args.repository.lower()
if not re.fullmatch(r'[a-z0-9][a-z0-9-]*/[a-z0-9][a-z0-9_.-]*', repo):
    parser.error('Expected a GitHub OWNER/REPOSITORY')
root = Path(__file__).resolve().parent.parent
policy_path = root / 'mkosi.profiles/barusu-bootc-ostree/mkosi.extra/usr/share/factory/etc/containers/policy.json'
registry_path = root / 'mkosi.profiles/barusu-bootc-ostree/mkosi.extra/usr/share/factory/etc/containers/registries.d/barusu-dev.yaml'
identity_path = root / 'image-identity.json'
image = f'ghcr.io/{repo.split("/")[0]}/barusu'
expected = {'repository': repo, 'image': image + ':latest', 'nvidia_image': image + '-nvidia:latest'}
if args.check:
    if not identity_path.exists() or json.loads(identity_path.read_text()) != expected:
        parser.error('Run configure-image.py for this repository with its signing public key before publishing')
    policy = json.loads(policy_path.read_text())['transports']['docker']
    for name in [image, image + '-nvidia']:
        if policy.get(name, [{}])[0].get('type') != 'sigstoreSigned':
            parser.error('Image signature policy does not match the configured repository')
    for name, ref in [('iso.toml', expected['image']), ('iso-nvidia.toml', expected['nvidia_image'])]:
        if ref not in (root / name).read_text():
            parser.error(f'{name} points to a different image')
    print('Image references and signature policy match', repo)
else:
    if args.public_key is None:
        parser.error('--public-key is required when configuring an image')
    key = args.public_key.read_text()
    if '-----BEGIN PUBLIC KEY-----' not in key or 'PRIVATE KEY' in key:
        parser.error('Supply the PUBLIC verification key, not a signing private key')
    policy = json.loads(policy_path.read_text())
    docker = policy['transports']['docker']
    for name in list(docker):
        if name.startswith('ghcr.io/'):
            del docker[name]
    for name in [image, image + '-nvidia']:
        docker[name] = [{'type': 'sigstoreSigned', 'keyPaths': ['/usr/share/pki/containers/barusu.pub'],
                         'signedIdentity': {'type': 'matchRepository'}}]
    policy_path.write_text(json.dumps(policy, indent=4) + '\n')
    registry_path.write_text(f'docker:\n  {image}:\n    use-sigstore-attachments: true\n  {image}-nvidia:\n    use-sigstore-attachments: true\n')
    (root / 'cosign.pub').write_text(key)
    (root / 'mkosi.extra/usr/share/barusu/project-url').write_text(f'https://github.com/{repo}\n')
    for filename, ref in [('iso.toml', expected['image']), ('iso-nvidia.toml', expected['nvidia_image'])]:
        path = root / filename
        path.write_text(re.sub(r'--transport registry \S+', '--transport registry ' + ref, path.read_text()))
    for filename, name in [('build-standard-bootc.yaml', 'barusu'),
                           ('build-nvidia-bootc.yaml', 'barusu-nvidia')]:
        path = root / '.github/workflows' / filename
        path.write_text(re.sub(r'image-name: \S+', 'image-name: ' + name, path.read_text()))
    # This assertion follows the configured identity rather than an upstream namespace.
    path = root / 'mkosi.profiles/barusu-bootc-ostree/mkosi.postinst.chroot'
    path.write_text('#!/usr/bin/env bash\nset -euo pipefail\nstat /usr/share/pki/containers/barusu.pub\ngrep -F -e "' + image + '" /usr/share/factory/etc/containers/policy.json\n')
    identity_path.write_text(json.dumps(expected, indent=2) + '\n')
    print('Configured', expected['image'], 'and', expected['nvidia_image'])
