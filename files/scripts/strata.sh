#!/bin/sh
# strata bootstrap :: fetch → verify → rehome at image build (barusu)
# Single third-party source, no COPRs, no mystery binaries. Receipts or silence.
set -eu

REPO="lgse/strata"
PREF="/usr/local"
BIN="${PREF}/bin/strata"
DOC="/usr/share/doc/strata"
API="https://api.github.com/repos/${REPO}/releases/latest"

abort() { echo "strata: $*" >&2; exit 1; }

# ---------- one API call: tag + full inventory ----------
BODY=$(curl -fsSL --retry 3 -H "Accept: application/vnd.github+json" "$API") \
  || abort "GitHub API unreachable (rate limit? try later)"
[ -n "$BODY" ] || abort "GitHub API answered empty"

TAG=$(printf '%s\n' "$BODY" | grep -o '"tag_name":[[:space:]]*"[^"]*"' | head -n1 | cut -d'"' -f4)
[ -n "$TAG" ] || abort "releases/latest answered but no tag found"
echo "strata: resolving ${TAG}"

ASSETS=$(printf '%s\n' "$BODY" | grep -o '"browser_download_url":[[:space:]]*"[^"]*"' | cut -d'"' -f4)
[ -n "$ASSETS" ] || abort "release carries no assets"
echo "strata: inventory:"
printf '%s\n' "$ASSETS" | sed 's/^/strata:   - /'

# ---------- candidate: x86_64 family; symbols/sidecars excluded ----------
X86=$(printf '%s\n' "$ASSETS" \
      | grep -Ei '(x86_64|amd64)' \
      | grep -Eiv '\.(debug|sha256|sha512|sig|asc|json|sbom|pem|txt|md)$') || true
[ -n "$X86" ] || abort "no usable x86_64 assets after exclusions (see inventory)"

TMP="$(mktemp -d /tmp/strata.XXXXXX)"

ASSET=$(printf '%s\n' "$X86" | grep -Ei '\.(tar\.zst|tar\.xz|tar\.gz|tgz|tar\.bz2|tar)$' | head -n1 || true)
[ -n "$ASSET" ] || ASSET=$(printf '%s\n' "$X86" | grep -Ei '\.deb$' | head -n1 || true)
[ -n "$ASSET" ] || ASSET=$(printf '%s\n' "$X86" | head -n1)
[ -n "$ASSET" ] || abort "nothing selectable (see inventory)"
echo "strata: selected $ASSET"

# ---------- download + TRUST LANE (compare-hashes method; filename-immune) ----------
curl -fsSL --retry 3 -o "$TMP/artifact" "$ASSET" || abort "download failed: $ASSET"
if curl -fsSL --retry 3 -o "$TMP/artifact.sha256" "${ASSET}.sha256" 2>/dev/null; then
  EXPECTED=$(cut -d' ' -f1 "$TMP/artifact.sha256" | head -n1)
  ACTUAL=$(sha256sum "$TMP/artifact" | cut -d' ' -f1)
  case "${EXPECTED:-}" in
    "$ACTUAL") echo "strata: sidecar digest OK ($ACTUAL)" ;;
    *) abort "sidecar digest MISMATCH — expected ${EXPECTED:-<empty>}, got $ACTUAL" ;;
  esac
else
  echo "strata: no sidecar published — proceeding, but the gap is NAMED"
fi

# ---------- extraction ----------
case "$ASSET" in
  *.tar*) tar -xf "$TMP/artifact" -C "$TMP" ;;
  *.deb)  if command -v dpkg-deb >/dev/null 2>&1; then
            mkdir -p "$TMP/x" && dpkg-deb -x "$TMP/artifact" "$TMP/x"
          else
            mkdir -p "$TMP/x" && ( cd "$TMP/x" && ar x "$TMP/artifact" && tar -xf data.tar.* )
          fi ;;
  *)      cp "$TMP/artifact" "$TMP/strata"; chmod 0755 "$TMP/strata" ;;
esac

# ---------- furniture receipts ----------
echo "strata: furniture:"
find "$TMP" -maxdepth 3 \( -iname '*.desktop' -o -ipath '*dbus*' -o -iname '*strata*' \) -print \
  | sed 's/^/strata:   /'

BINPATH=$(find "$TMP" -type f -name 'strata*' ! -name '*.debug' ! -name '*.sha256' | head -n1 || true)
[ -n "$BINPATH" ] || BINPATH=$(find "$TMP" -type f -perm -u+x ! -name '*.sha256' | head -n1 || true)
[ -n "$BINPATH" ] || abort "no executable found in archive (see furniture)"

install -d -m 0755 "${PREF}/bin" "$DOC"
install -m 0755 "$BINPATH" "$BIN"
echo "strata: rehomed $BIN"
sha256sum "$BIN" | sed 's/^/strata:   /'

printf 'TAG=%s\nBUILD_DATE=%s\n' "$TAG" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" > "$DOC/BUILD_INFO"
cp /etc/os-release "$DOC/os-release"
rm -rf "$TMP"
echo "strata: done"
