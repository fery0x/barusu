"""Execute recipe shell bodies with stubbed system commands; never modify the host."""
from pathlib import Path
import os
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
RECIPES = {}
name = None
for line in (ROOT / 'mkosi.extra/usr/share/barusu/just/00-system.just').read_text().splitlines():
    match = re.fullmatch(r'([a-z][a-z-]*):', line)
    if match:
        name = match[1]
        RECIPES[name] = []
    elif line.startswith('    ') and name:
        RECIPES[name].append(line[4:])

class RecipeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.calls = self.root / 'calls'
        self.home = self.root / 'home'
        self.home.mkdir()
        for command in ['gum', 'bootc', 'systemctl', 'chezmoi', 'dms-greeter', 'flatpak']:
            path = self.bin / command
            path.write_text('#!/bin/bash\nprintf "%s\\n" "' + command + ' $*" >> "$CALLS"\n' + ('exit "${GUM_EXIT:-0}"\n' if command == 'gum' else 'exit 0\n'))
            path.chmod(0o755)
        sudo = self.bin / 'sudo'
        sudo.write_text('#!/bin/bash\nexec "$@"\n')
        sudo.chmod(0o755)
        self.env = dict(os.environ, HOME=str(self.home), TMPDIR=str(self.root), CALLS=str(self.calls), PATH=str(self.bin)+':'+os.environ['PATH'])

    def run_recipe(self, name, decline=False):
        return subprocess.run(['bash', '-e', '-c', '\n'.join(RECIPES[name])], env=dict(self.env, GUM_EXIT='1' if decline else '0'), text=True, capture_output=True, check=True)

    def test_all_recipe_shell_syntax(self):
        for name, body in RECIPES.items():
            subprocess.run(['bash', '-n'], input='\n'.join(body), text=True, check=True)

    def test_update_stages_without_reboot(self):
        self.run_recipe('update')
        self.assertEqual(self.calls.read_text().splitlines(), ['bootc update', 'bootc status'])

    def test_cancel_prevents_changes(self):
        for name in ['update-dotfiles','update-greeter','enable-updates','disable-updates']:
            self.calls.write_text('')
            self.run_recipe(name, decline=True)
            self.assertTrue(all(line.startswith('gum confirm') for line in self.calls.read_text().splitlines()))
        self.assertFalse((self.home/'.config').exists())

    def test_timer_scope(self):
        self.run_recipe('enable-updates')
        self.run_recipe('disable-updates')
        calls = self.calls.read_text()
        self.assertIn('systemctl enable --now bootc-fetch-apply-updates.timer', calls)
        self.assertIn('systemctl disable --now bootc-fetch-apply-updates.timer', calls)
        self.assertNotIn('reboot', '\n'.join(x for x in calls.splitlines() if not x.startswith('gum')))

    def test_chezmoi_has_no_force(self):
        self.run_recipe('update-dotfiles')
        calls = self.calls.read_text()
        self.assertIn('chezmoi apply -S /usr/share/barusu/zdots --config '+str(self.home)+'/.config/barusu/chezmoi/chezmoi.toml',calls)
        self.assertNotIn('--force', calls)

    def test_report_is_local_and_private(self):
        result = self.run_recipe('diagnostics')
        files = list(self.root.glob('barusu-report.*'))
        self.assertEqual(len(files),1)
        self.assertEqual(files[0].stat().st_mode & 0o777, 0o600)
        self.assertIn(str(files[0]), result.stdout)
        self.assertIn('Barusu diagnostics', files[0].read_text())

if __name__ == '__main__':
    unittest.main()
