# Validation and migration

## Completed here

- JSON, TOML, XML/SVG, Python, and shell syntax checks.
- Required Niri include resolution and removed-launcher reference checks.
- Required/removed explicit package-selection checks.
- Chezmoi source-tree, restored preset/service, and greeter-target consistency checks.
- The previous custom-initializer tests were removed with that implementation.
- Whitespace checks and workflow YAML parsing.
- Six bjust recipe-body tests with stubbed system commands: shell syntax, staged
  updates, canceled prompts, timer scope, non-forced Chezmoi, private local reports.
  Actual Just parsing runs in the image build; these tests exercise shell behavior.

These are source checks, not evidence of a bootable image. The Fedora dependency
solve, imported Homebrew payload, actual Niri parser and RPM-provided services
need a build host. Replacing `@standard` and `@base-graphical` with explicit
infrastructure requires a full build and VM test. `@core` and hard dependencies
remain. Do not force-remove libraries or apps that return as hard dependencies.

## Build and VM gates

1. Build and run `bootc container lint` for each architecture and NVIDIA variant.
   Review `/usr/share/barusu/build-info/packages.tsv` in the built image.
2. Boot a fresh installed VM. Verify greeter login, password authentication,
   keyring unlocking, session startup, polkit prompts, Ghostty and Homebrew PATH.
3. Verify lock/unlock, lid close, idle lock, suspend/resume, brightness, volume,
   media keys, Wi-Fi/Bluetooth and input/accessibility support.
4. Verify Niri screenshot keys, clipboard, Flatpak file picker and screen sharing.
   DMS's own screenshot UI also needs testing without an external editor.
5. Install a CLI with Homebrew and a GUI with Flatpak; confirm no automatic
   Text Editor/Bazaar/DankCalendar installation.
6. As an ordinary user, run `podman info`, start a rootless container, and test
   networking and a persistent volume. Check subordinate ID ranges and the
   RPM-provided newuidmap/newgidmap permissions/capabilities.
7. Check the bootc service uses `bootc update --quiet`, without `--apply`, and the
   timer is weekly. Stage an update, reboot into it, and test rollback. Pause
   automatic updates while deliberately remaining on a rollback deployment.
8. Test on real target hardware, particularly NVIDIA, fingerprint readers, VPNs,
   printing, and hybrid graphics. The Xwayland Satellite pin and existing NVIDIA
   Secure Boot limitations are retained.

Before release, also test `bjust` with the installed Just/Gum versions, including
greeter synchronization and interactive Chezmoi conflict handling.

## Existing installations

Rebasing changes the OS deployment, but installed Flatpaks, Homebrew content,
home directories and administrator changes in `/etc` can persist. They are not
silently deleted. Back up before migration; test a rebase separately from a
fresh installation.

Chezmoi's original initialization/update services and timer manage the trimmed
source at `/usr/share/barusu/zdots`. Retired shell profile targets remain no-ops
for old `/etc` symlinks. The replacement initializer has been removed completely.
Earlier Zirconium and minimal-image system Niri include paths forward to the restored
Chezmoi source. No automatic conversion of customized files is performed by a
new migration tool.

For an account previously using the first minimal archive, stop the old initializer
and enable Chezmoi's timer after rebasing. Missing-unit messages are expected if
that earlier image was never installed:

```sh
systemctl --user disable --now barusu-user-defaults.service foot-server.socket foot-server.service
sudo systemctl disable --now uupd.timer flatpak-preinstall.service cardwired.service
systemctl --user daemon-reload
systemctl --user enable chezmoi-init.service
systemctl --user start chezmoi-init.service
systemctl --user enable --now chezmoi-update.timer
sudo systemctl enable --now bootc-fetch-apply-updates.timer
```

If Chezmoi was already initialized, the init service's upstream condition skips it.
Use `chezmoi diff` and `chezmoi apply` with the source/config paths documented in
README to review and apply new defaults. Retain backups and test first login and
conflict handling before release. Review customized settings for old Foot terminal
overrides, visualization, wallpapers and screenshot-editor overrides. Installed
Flatpaks, unrelated user files and third-party plugins are not removed.

If you have custom Chezmoi configuration, review and migrate it from
`~/.config/zirconium/chezmoi/chezmoi.toml` to
`~/.config/barusu/chezmoi/chezmoi.toml`. Update any personal scripts using old
paths. Existing greeter symlinks have compatibility targets in the image.

## Maintenance

Bootc filesystem, SELinux, initramfs, legacy group repair and signing integration
are retained. The initramfs configuration's `[Contents]` typo was corrected to
`[Content]`; the NVIDIA preset directory spelling was fixed.

The vendored defaults replace the zdots submodule; compare upstream improvements
against the recorded revision. Jackrabbit, sysupdate, Rawhide and unused live-ISO
paths no longer have jobs in this project. The bootc-image-builder installer
workflow remains.

External inputs still use moving references, including the Homebrew OCI payload
and repository packages. This change does not claim reproducible dependency
versions. Pin those separately if required.
