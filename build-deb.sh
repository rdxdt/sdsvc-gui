#!/usr/bin/env bash
#
# Package the already-compiled src/sdsvcgui binary into a .deb.
#
# Usage: ./build-deb.sh [version]
#   version defaults to the latest entry in debian/changelog.
#
# Build the binary first (Lazarus IDE or `lazbuild src/sdsvcgui.lpi`).
# The package is written to dist/.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

PKG_NAME="sdsvcgui"
BINARY="src/$PKG_NAME"
STAGE_DIR="build/deb"
PKG_DIR="$STAGE_DIR/$PKG_NAME"
DIST_DIR="dist"
ICON_SIZES=(16 22 24 32 48 64 96 128 256 512)

die() { echo "error: $*" >&2; exit 1; }

for tool in dpkg-deb dpkg-parsechangelog dpkg-shlibdeps strip gzip md5sum; do
    command -v "$tool" >/dev/null || die "'$tool' not found (install dpkg-dev and binutils)"
done

[[ -x "$BINARY" ]] || die "$BINARY not found; compile the project first"

VERSION="${1:-$(dpkg-parsechangelog -S Version)}"
ARCH="$(dpkg --print-architecture)"
MAINTAINER="$(sed -n 's/^Maintainer: //p' debian/control)"
HOMEPAGE="$(sed -n 's/^Homepage: //p' debian/control)"
DEB_FILE="$DIST_DIR/${PKG_NAME}_${VERSION}_${ARCH}.deb"

echo "==> Packaging $PKG_NAME $VERSION ($ARCH)"

rm -rf "$STAGE_DIR"
mkdir -p "$PKG_DIR/DEBIAN" "$DIST_DIR"

# Binary
install -D -m 0755 "$BINARY" "$PKG_DIR/usr/bin/$PKG_NAME"
strip --strip-unneeded --remove-section=.comment --remove-section=.note \
    "$PKG_DIR/usr/bin/$PKG_NAME"

# Desktop entry and icons
install -D -m 0644 "debian/$PKG_NAME.desktop" \
    "$PKG_DIR/usr/share/applications/$PKG_NAME.desktop"
for s in "${ICON_SIZES[@]}"; do
    install -D -m 0644 "img/$PKG_NAME-${s}x${s}.png" \
        "$PKG_DIR/usr/share/icons/hicolor/${s}x${s}/apps/$PKG_NAME.png"
done

# Documentation
DOC_DIR="$PKG_DIR/usr/share/doc/$PKG_NAME"
install -D -m 0644 debian/copyright "$DOC_DIR/copyright"
gzip -9n -c debian/changelog > "$DOC_DIR/changelog.gz"
chmod 0644 "$DOC_DIR/changelog.gz"

# Shared library dependencies, detected from the binary
SHLIBS="$(dpkg-shlibdeps -O -e"$PKG_DIR/usr/bin/$PKG_NAME" 2>/dev/null \
    | sed -n 's/^shlibs:Depends=//p')"
DEPENDS="${SHLIBS:+$SHLIBS, }systemd"
[[ "$SHLIBS" == *libgtk2.0-0t64* ]] || DEPENDS="libgtk2.0-0t64, $DEPENDS"

INSTALLED_SIZE="$(du -sk --exclude=DEBIAN "$PKG_DIR" | cut -f1)"

cat > "$PKG_DIR/DEBIAN/control" <<EOF
Package: $PKG_NAME
Version: $VERSION
Architecture: $ARCH
Maintainer: $MAINTAINER
Installed-Size: $INSTALLED_SIZE
Depends: $DEPENDS
Section: admin
Priority: optional
Homepage: $HOMEPAGE
Description: graphical manager for systemd services
 SystemD Service Manager is a small Lazarus/LCL (GTK2) application that
 lists systemd units and lets you start, stop, restart, enable and
 disable services through systemctl.
EOF

(cd "$PKG_DIR" && find usr -type f -print0 | sort -z | xargs -0 md5sum) \
    > "$PKG_DIR/DEBIAN/md5sums"

find "$PKG_DIR" -type d -exec chmod 0755 {} +

dpkg-deb --root-owner-group --build "$PKG_DIR" "$DEB_FILE" >/dev/null

echo "==> Built $DEB_FILE"
echo "    Depends: $DEPENDS"
echo "    Install with: sudo apt install ./$DEB_FILE"
