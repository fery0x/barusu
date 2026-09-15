# Barusu system helpers. Application installation remains with brew/flatpak/podman.

# List the available administration commands.
default:
    @/usr/bin/just --justfile /usr/share/barusu/just/00-system.just --list

# Stage an OS update; reboot later when convenient.
update:
    #!/usr/bin/env bash
    set -euo pipefail
    sudo bootc update
    sudo bootc status
    echo "Any staged deployment will activate on your next reboot."

# Show booted/staged deployments and automatic update scheduling.
status:
    #!/usr/bin/env bash
    set -euo pipefail
    sudo bootc status
    systemctl list-timers --all --no-pager bootc-fetch-apply-updates.timer

# Show the latest 200 system journal entries from this boot.
logs:
    sudo journalctl --boot --no-pager --lines=200

# Write a private local diagnostic report; nothing is uploaded.
diagnostics:
    #!/usr/bin/env bash
    set -euo pipefail
    umask 077
    report="$(mktemp "${TMPDIR:-/tmp}/barusu-report.XXXXXX")"
    {
        echo "Barusu diagnostics"
        date --iso-8601=seconds
        uname -a
        echo "--- OS deployment ---"
        sudo bootc status || echo "Could not read bootc status."
        echo "--- Failed system units ---"
        systemctl --failed --no-pager || true
        echo "--- Failed user units ---"
        systemctl --user --failed --no-pager || true
        echo "--- Update schedule ---"
        systemctl list-timers --all --no-pager bootc-fetch-apply-updates.timer || true
        echo "--- Flatpak applications ---"
        flatpak list --app --columns=application,version,installation || true
    } > "$report" 2>&1
    echo "Saved locally: $report"
    echo "Review this report before sharing it."

# Review changes between your configuration and the image's Chezmoi defaults.
diff-dotfiles:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "$HOME/.config/barusu/chezmoi"
    touch "$HOME/.config/barusu/chezmoi/chezmoi.toml"
    chezmoi diff -S /usr/share/barusu/zdots --config "$HOME/.config/barusu/chezmoi/chezmoi.toml"

# Apply image defaults interactively, without forcing conflicts.
update-dotfiles:
    #!/usr/bin/env bash
    set -euo pipefail
    gum confirm "Apply Barusu's desktop defaults? Existing conflicts will be handled by Chezmoi." || exit 0
    mkdir -p "$HOME/.config/barusu/chezmoi"
    touch "$HOME/.config/barusu/chezmoi/chezmoi.toml"
    chezmoi apply -S /usr/share/barusu/zdots --config "$HOME/.config/barusu/chezmoi/chezmoi.toml"

# Synchronize your DMS theme with the system greeter, leaving PAM setup alone.
update-greeter:
    #!/usr/bin/env bash
    set -euo pipefail
    gum confirm "Sync this user's theme to the system greeter? This can adjust greeter access permissions." || exit 0
    DMS_PRIVESC=sudo dms-greeter sync
    echo "Log out and back in if greeter group membership changed."

# Enable weekly OS update staging, without automatic reboot.
enable-updates:
    #!/usr/bin/env bash
    set -euo pipefail
    gum confirm "Enable weekly OS update staging? Reboots remain manual." || exit 0
    sudo systemctl enable --now bootc-fetch-apply-updates.timer

# Disable the weekly timer; an already running update is not interrupted.
disable-updates:
    #!/usr/bin/env bash
    set -euo pipefail
    gum confirm --default=false "Disable automatic OS update staging?" || exit 0
    sudo systemctl disable --now bootc-fetch-apply-updates.timer
