# Barusu

Fedora 44 bootc source project with Niri, DankMaterialShell, DMS greeter/greetd,
Ghostty, Flatpak, Homebrew, and Podman. CLI applications belong in Homebrew;
GUI applications belong in Flatpak; containers and services belong in Podman.
No GUI application bundle is preinstalled. Chezmoi manages the trimmed desktop
configuration. The OS includes Just and Gum to support `bjust`, a small set of
system-administration recipes adapted from Zirconium. Universal Blue Homebrew
integration remains in place.

The OS retains graphics, firmware, audio, networking, authentication, portals,
printing, accessibility, input methods, power management, removable-device and
virtual-machine support. DMS search, theming, sounds, and hardware-key helpers
remain. Cava visualization and external screenshot editing are disabled;
screenshot keys use Niri directly. A separate NVIDIA profile retains the driver,
build requirements, and container GPU integration.

## Build

Use a Fedora-capable Linux build host with mkosi, Podman, and just. CI retains
the upstream pinned mkosi action. This archive contains all required defaults
and assets; there are no submodules to initialize.

```sh
python3 scripts/validate-source.py
python3 -m unittest discover -s tests -v
just build
sudo just load
sudo just lint
```

For NVIDIA:

```sh
sudo mkosi -B --profile=base,base-desktop,bootc-ostree,brew,barusu-bootc-ostree,nvidia
```

The build hook runs `niri validate` and checks the required desktop binaries.
The resulting image records its resolved RPM list in
`/usr/share/barusu/build-info/packages.tsv`. Inspect this manifest before
release: hard dependencies remain allowed even when a package is omitted from
intentional selections. DNF `exclude_from_weak` prevents removed apps from
returning merely as recommendations while retaining other weak dependencies.

## Publish or make an installer

The project has not been published. Configure the actual fork identity and
PUBLIC key matching its `SIGNING_SECRET` before enabling publication:

```sh
python3 scripts/configure-image.py YOUR-OWNER/YOUR-REPOSITORY --public-key /path/to/cosign.pub
python3 scripts/configure-image.py YOUR-OWNER/YOUR-REPOSITORY --check
```

Commit those changes in your fork, configure the signing secret, then set the
GitHub repository variable `BARUSU_PUBLISH=true`. OCI and installer workflows
verify the identity before publishing/building an installer. S3 upload requires
the existing S3 secrets. Local build/lint does not require publication settings.

Until configured, installer references use `REPLACE_OWNER` and the public key is
an inherited placeholder. Do not use these installer TOMLs for a release until
configured. The helper sets `ghcr.io/YOUR-OWNER/barusu:latest` and its NVIDIA
variant, along with the matching public key and project URL.

## bjust

Run `bjust` to list commands, or `bjust --dry-run COMMAND` to inspect a recipe.
Run it as your regular user; individual system operations request sudo as needed.

| Command | Purpose |
| --- | --- |
| `bjust update` | Stage an OS update without rebooting |
| `bjust status` | Show booted/staged deployments and the update timer |
| `bjust logs` | Show recent system logs |
| `bjust diagnostics` | Save a private local report; no upload |
| `bjust diff-dotfiles` | Review Chezmoi changes |
| `bjust update-dotfiles` | Apply defaults interactively, without force |
| `bjust update-greeter` | Sync DMS greeter theme/settings without requesting PAM changes |
| `bjust enable-updates` | Enable weekly OS update staging |
| `bjust disable-updates` | Disable the update timer |

Gum supplies confirmation prompts. These recipes do not install applications,
reset the machine, change boot images, or reboot automatically. Use Homebrew,
Flatpak and Podman directly for their respective software.

## Defaults and updates

Trimmed Niri/DMS/Ghostty defaults live in the Chezmoi source directory
`/usr/share/barusu/zdots`. Barusu's original Chezmoi initialization service,
update service and daily timer are restored. DMS waits for the initialization
attempt; the system Niri fallback remains available. System-only files are
excluded from Chezmoi's home-directory target with `.chezmoiignore`.

Put Niri overrides in `~/.config/niri/local.kdl` or `/etc/niri/local.kdl`.
Keep the optional DMS includes for generated display settings and colors.
To inspect changes and apply the image's defaults manually:

```sh
chezmoi diff -S /usr/share/barusu/zdots --config "$HOME/.config/barusu/chezmoi/chezmoi.toml"
chezmoi apply -S /usr/share/barusu/zdots --config "$HOME/.config/barusu/chezmoi/chezmoi.toml"
```

The update service retains upstream's conflict-skip behavior. Keep personal
configuration in the documented override files and review conflicts manually.
To stop automatic configuration updates, disable `chezmoi-update.timer` with
`systemctl --user disable --now chezmoi-update.timer`.

Universal Blue Homebrew integration is still imported from
`ghcr.io/ublue-os/brew:latest`, with its setup and brew-proxy services retained.

Weekly bootc updates are staged without automatic reboot; reboot when convenient
to activate them. `sudo bootc update` updates manually. Homebrew and Flatpak apps
remain independently managed. Flatpak remote setup remains, without preinstalls.

## Status and sources

Offline source validation passed. Chezmoi execution and first-login behavior
require validation on the build/test host. This editing environment
has no mkosi, Podman, DNF, or Niri, so no image was built or boot-tested.
See [validation and migration](docs/validation-and-migration.md) and the
[explicit package selection delta](docs/package-changes.json).

Sources: Zirconium `d72f81c0117e449976728e20441173ef2ecf1b2c`, zdots
`ba17a3aea5ab620471394779d1857788e9f3de33`, assets
`83dcc94565b0b5c8f0a6ed5f8e171ad8873c56e2`. The supplied zdots archive was not
verified against the original repository's gitlink. Old Zirconium logos and installer overlays are removed; the default Fedora
installer appearance is retained. The desktop uses a neutral background.
Upstream licenses are preserved.
