#!/usr/bin/env bash
set -euo pipefail
# barusu :: strata installer — channel: latest release
# digest-checked against upstream sidecar when one is published,
# receipts written to build log + /usr/share/doc/strata/BUILD_INFO

REPO="lgse/strata"
API="https://api.github.com/repos/${REPO}/releases/latest"

# --- resolve latest release -------------------------------------------------
RELEASE_JSON=$(curl -fsSL "$API")
TAG=$(echo "$RELEASE_JSON" | grep -m1 '"tag_name"' | cut -d'"' -f4)

ASSET_URL=$(echo "$RELEASE_JSON" | grep browser_download_url | \
            grep -E 'x86_64|amd64' | grep -Ev 'sha256|sig' | head -1 | cut -d'"' -f4)

[ -n "$ASSET_URL" ] || { echo "strata: no x86_64 asset in $TAG"; exit 1; }

echo "strata: resolving $TAG -> $ASSET_URL"

# --- download ----------------------------------------------------------------
TMP=$(mktemp -d)
curl -fsSL -o "$TMP/strata.asset" "$ASSET_URL"

# --- digest verification (when upstream publishes a sidecar) -----------------
SIDE_URL="${ASSET_URL}.sha256"
if curl -fsSL -o "$TMP/side.sha256" "$SIDE_URL" 2>/dev/null; then
  (cd "$TMP" && \
   sha256sum strata.asset | awk '{print $1}' | \
   grep -qx "$(awk '{print $1}' side.sha256)" && \
   echo "strata $TAG: sidecar digest OK") || { echo "strata: digest mismatch"; exit 1; }
else
  echo "strata $TAG: no sidecar digest published by upstream — skipping check"
fi

# --- extract (ar: binutils, ships in base) -----------------------------------
case "$ASSET_URL" in
  *.tar.gz|*.tgz|*.tar.xz)
    tar -xf "$TMP/strata.asset" -C "$TMP"
    install -m755 "$TMP"/*strata* /usr/bin/strata 2>/dev/null ||
      install -m755 "$TMP/usr/bin/strata" /usr/bin/strata
    ;;
  *.deb)
    ar p "$TMP/strata.asset" data.tar.* | tar -xz -C "$TMP"
    install -m755 "$TMP/usr/bin/strata" /usr/bin/strata
    ;;
  *) echo "strata: unknown asset format: $ASSET_URL"; exit 1 ;;
esac

# --- furniture: desktop entry + FileManager1 D-Bus activation ----------------
# whatever the archive ships gets installed; -print writes receipts into the
# build log so we never install naming on faith
find "$TMP" -name '*.desktop'              -exec install -Dm644 {} /usr/share/applications/    \; -print
find "$TMP" -name '*FileManager1*.service' -exec install -Dm644 {} /usr/share/dbus-1/services/ \; -print

# --- receipt baked into the image ---------------------------------------------
mkdir -p /usr/share/doc/strata
printf 'channel=latest\ntag=%s\nasset=%s\n' "$TAG" "$ASSET_URL" > /usr/share/doc/strata/BUILD_INFO

rm -rf "$TMP"
echo "strata $TAG: installed"
