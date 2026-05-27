#!/bin/bash
# Builds the pi-wayvnc-macos .deb inside the trixie-slim container.
# Expects /src bind-mounted from the repo root and /out bind-mounted for output.
set -euo pipefail

VERSION="${VERSION:-1.0.0-1}"
ARCH="$(dpkg --print-architecture)"
STAGING=/build/staging
PKG=/build/pkg
PREFIX=/opt/pi-wayvnc-macos

if [ "$ARCH" != "arm64" ]; then
    echo "WARNING: building on $ARCH, not arm64 — produced .deb will not install on Pi" >&2
fi

# /src is read-only; copy sources into a writable build location.
rm -rf /build
mkdir -p "$STAGING" "$PKG$PREFIX"/{bin,lib,share}
cp -a /src/sources /build/src
SRC=/build/src

export PKG_CONFIG_PATH="$STAGING/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
# DT_RUNPATH (overridable by LD_LIBRARY_PATH) instead of legacy DT_RPATH:
export LDFLAGS="-Wl,--enable-new-dtags"

echo "==> Building aml ($(git -C $SRC/aml rev-parse --short HEAD 2>/dev/null || echo no-git))"
cd "$SRC/aml"
meson setup build --buildtype=release \
    --prefix="$STAGING" --libdir=lib \
    -Ddefault_library=shared --wipe
ninja -C build
ninja -C build install

echo "==> Building neatvnc ($(git -C $SRC/neatvnc rev-parse --short HEAD 2>/dev/null || echo no-git))"
cd "$SRC/neatvnc"
meson setup build --buildtype=release \
    --prefix="$STAGING" --libdir=lib \
    -Dtls=enabled -Dnettle=enabled -Dh264=enabled \
    -Dgbm=enabled -Djpeg=enabled \
    -Dtests=false -Dexamples=false -Dbenchmarks=false \
    --wipe
ninja -C build
ninja -C build install

echo "==> Building wayvnc ($(git -C $SRC/wayvnc rev-parse --short HEAD 2>/dev/null || echo no-git))"
cd "$SRC/wayvnc"
meson setup build --buildtype=release \
    --prefix="$STAGING" --libdir=lib \
    -Dpam=disabled -Dscreencopy-dmabuf=enabled \
    --wipe
ninja -C build
ninja -C build install

# ---------------------------------------------------------------------------
# Assemble /opt/pi-wayvnc-macos tree
# ---------------------------------------------------------------------------
echo "==> Staging /opt tree"
install -m 0755 "$STAGING/bin/wayvnc"    "$PKG$PREFIX/bin/wayvnc"
install -m 0755 "$STAGING/bin/wayvncctl" "$PKG$PREFIX/bin/wayvncctl"

# Copy versioned .so + soname symlinks; drop unversioned dev symlinks
cp -a "$STAGING/lib/libaml.so.1"*     "$PKG$PREFIX/lib/"
cp -a "$STAGING/lib/libneatvnc.so.1"* "$PKG$PREFIX/lib/"
rm -f "$PKG$PREFIX/lib/libaml.so" "$PKG$PREFIX/lib/libneatvnc.so"

# Set DT_RUNPATH = $ORIGIN/../lib so binaries find bundled libs without
# needing LD_LIBRARY_PATH.
echo "==> Setting RPATH on bundled ELFs"
for f in "$PKG$PREFIX/bin/wayvnc" \
         "$PKG$PREFIX/bin/wayvncctl" \
         "$PKG$PREFIX/lib"/libneatvnc.so.1.0.0; do
    patchelf --set-rpath '$ORIGIN/../lib' "$f"
done

echo "==> Stripping binaries"
strip --strip-unneeded "$PKG$PREFIX"/bin/wayvnc "$PKG$PREFIX"/bin/wayvncctl
strip --strip-unneeded "$PKG$PREFIX"/lib/libaml.so.1.0.0 || true
strip --strip-unneeded "$PKG$PREFIX"/lib/libneatvnc.so.1.0.0 || true

# Shared libraries should be 0644, not 0755 (Debian convention).
chmod 0644 "$PKG$PREFIX"/lib/*.so.*

# Sanity-check RPATH and bundled lib resolution
echo "==> Verifying RPATH and library resolution"
for f in "$PKG$PREFIX/bin/wayvnc" "$PKG$PREFIX/bin/wayvncctl" \
         "$PKG$PREFIX/lib"/libneatvnc.so.1.0.0; do
    rp=$(patchelf --print-rpath "$f")
    if [ "$rp" != '$ORIGIN/../lib' ]; then
        echo "ERROR: $f has unexpected RPATH: $rp" >&2
        exit 1
    fi
done

# ldd inside the container with LD_LIBRARY_PATH unset should resolve our libs
# from somewhere under $PKG$PREFIX/ (the path may include "bin/.." because of
# how $ORIGIN/../lib expands).
unset LD_LIBRARY_PATH
LDD_OUT=$(LD_LIBRARY_PATH= ldd "$PKG$PREFIX/bin/wayvnc")
neatvnc_line=$(echo "$LDD_OUT" | grep -E '^\s*libneatvnc\.so\.1' || true)
aml_line=$(echo "$LDD_OUT" | grep -E '^\s*libaml\.so\.1' || true)
case "$neatvnc_line" in
    *"$PKG$PREFIX"/*) ;;
    *)
        echo "ERROR: wayvnc resolves libneatvnc.so.1 from outside the bundle:" >&2
        echo "  $neatvnc_line" >&2
        exit 1 ;;
esac
case "$aml_line" in
    *"$PKG$PREFIX"/*) ;;
    *)
        echo "ERROR: wayvnc resolves libaml.so.1 from outside the bundle:" >&2
        echo "  $aml_line" >&2
        exit 1 ;;
esac
echo "    OK: bundled libs resolved from /opt/pi-wayvnc-macos/lib/"

# ---------------------------------------------------------------------------
# Helper scripts and example config
# ---------------------------------------------------------------------------
echo "==> Installing helper scripts"
install -m 0755 /src/files/pi-wayvnc-macos-run.sh        "$PKG$PREFIX/bin/"
install -m 0755 /src/files/pi-wayvnc-macos-enable        "$PKG$PREFIX/bin/"
install -m 0755 /src/files/pi-wayvnc-macos-disable       "$PKG$PREFIX/bin/"
install -m 0755 /src/files/pi-wayvnc-macos-show-password "$PKG$PREFIX/bin/"
install -m 0644 /src/files/config.macos.example          "$PKG$PREFIX/share/"
install -m 0644 /src/README.md                           "$PKG$PREFIX/share/"
install -m 0644 /src/sources/manifest.txt                "$PKG$PREFIX/share/"

# Standard /usr/share/doc/<pkg>/ tree: gzipped changelog + copyright.
DOCDIR="$PKG/usr/share/doc/pi-wayvnc-macos"
install -d "$DOCDIR"
install -m 0644 /src/debian/copyright "$DOCDIR/copyright"
gzip -9n -c /src/debian/changelog > "$DOCDIR/changelog.Debian.gz"
chmod 0644 "$DOCDIR/changelog.Debian.gz"

# Lintian overrides for the warnings we intentionally ignore.
LINTDIR="$PKG/usr/share/lintian/overrides"
install -d "$LINTDIR"
install -m 0644 /src/debian/lintian-overrides "$LINTDIR/pi-wayvnc-macos"

# Systemd drop-in installed DISABLED so postinst doesn't break the live service
install -d "$PKG/etc/systemd/system/wayvnc.service.d"
install -m 0644 /src/files/pi-wayvnc-macos.conf \
    "$PKG/etc/systemd/system/wayvnc.service.d/pi-wayvnc-macos.conf.disabled"

# ---------------------------------------------------------------------------
# Debian metadata
# ---------------------------------------------------------------------------
echo "==> Generating Debian metadata"
install -d "$PKG/DEBIAN"
install -m 0755 /src/debian/postinst "$PKG/DEBIAN/postinst"
install -m 0755 /src/debian/prerm    "$PKG/DEBIAN/prerm"
install -m 0755 /src/debian/postrm   "$PKG/DEBIAN/postrm"

# Auto-derive shlib deps from the actual ELFs.
# dpkg-shlibdeps must be run from a dir containing debian/control IN
# SOURCE-PACKAGE FORMAT (with a `Source:` stanza first). Write a minimal
# stub for that purpose — it is never installed.
TMPDEB=$(mktemp -d)
mkdir -p "$TMPDEB/debian"
cat > "$TMPDEB/debian/control" <<'EOF'
Source: pi-wayvnc-macos
Section: admin
Priority: optional
Maintainer: build <build@localhost>

Package: pi-wayvnc-macos
Architecture: any
Description: stub for dpkg-shlibdeps
 Stub control file used only at build time.
EOF
cd "$TMPDEB"
SHLIB_INPUT_DIR="$PKG"
dpkg-shlibdeps -O --ignore-missing-info \
    "$SHLIB_INPUT_DIR/opt/pi-wayvnc-macos/bin/wayvnc" \
    "$SHLIB_INPUT_DIR/opt/pi-wayvnc-macos/bin/wayvncctl" \
    "$SHLIB_INPUT_DIR/opt/pi-wayvnc-macos/lib/libneatvnc.so.1.0.0" > shlibs.out 2>shlibs.err || {
        cat shlibs.err >&2
        echo "ERROR: dpkg-shlibdeps failed" >&2
        exit 1
    }
SHLIB_DEPS=$(sed -n 's/^shlibs:Depends=//p' shlibs.out)
if [ -z "$SHLIB_DEPS" ]; then
    echo "ERROR: dpkg-shlibdeps produced no Depends:" >&2
    cat shlibs.err >&2
    exit 1
fi
echo "    auto-derived shlib deps: $SHLIB_DEPS"

# Substitute placeholders in control.in → DEBIAN/control
sed -e "s|@VERSION@|${VERSION}|g" \
    -e "s|@ARCH@|${ARCH}|g" \
    -e "s|@SHLIB_DEPS@|${SHLIB_DEPS}|g" \
    /src/debian/control.in > "$PKG/DEBIAN/control"

# md5sums for the package contents
(cd "$PKG" && find opt etc usr -type f -exec md5sum {} \; > DEBIAN/md5sums)

# ---------------------------------------------------------------------------
# Build the .deb
# ---------------------------------------------------------------------------
echo "==> Building .deb"
DEB_NAME="pi-wayvnc-macos_${VERSION}_${ARCH}.deb"
dpkg-deb --root-owner-group --build "$PKG" "/out/$DEB_NAME"

echo "==> Lintian (informational)"
lintian "/out/$DEB_NAME" || true

echo
echo "==> Built: /out/$DEB_NAME"
ls -lh "/out/$DEB_NAME"
