#!/usr/bin/env bash
#
# Builds Idris-x86_64.AppImage: the Linux app as one file that runs on any
# recent desktop Linux. Used by .github/workflows/release.yml and by hand.
#
# Inside it:
#   usr/lib/idris/            the Flutter bundle (idris, lib/, data/)
#   usr/lib/idris/extractor/  the NewPipe helper (linux/extractor) with a
#                             Java runtime trimmed to the modules it needs
#   usr/lib/                  libmpv and the libraries it needs, but not
#                             what every desktop has (GTK, GLib, graphics,
#                             audio): bundling those breaks themes and sound
#
# Needs: Flutter, a JDK 17 (jlink), libmpv, and the Linux build
# requirements in the README. linuxdeploy is downloaded once into
# build/appimage-tools.
#
# Usage: linux/build_appimage.sh [output dir]   (default: build/appimage)
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mkdir -p "${1:-$REPO/build/appimage}" && cd "${1:-$REPO/build/appimage}" && pwd)"
TOOLS="$REPO/build/appimage-tools"
APPDIR="$OUT/AppDir"
APP="$APPDIR/usr/lib/idris"
cd "$REPO"

echo "== Flutter release build"
flutter build linux --release

echo "== NewPipe helper"
./linux/extractor/gradlew -p linux/extractor installDist -q

echo "== AppDir"
rm -rf "$APPDIR"
mkdir -p "$APP" "$APPDIR/usr/share/applications" "$APPDIR/usr/share/icons/hicolor/256x256/apps"
cp -r build/linux/x64/release/bundle/. "$APP/"
mkdir -p "$APP/extractor"
cp -r linux/extractor/build/install/idris-extractor/lib "$APP/extractor/lib"

# The Java modules the helper needs: jdeps --print-module-deps on its jars,
# plus jdk.crypto.ec, which TLS loads at runtime (YouTube's HTTPS fails
# with a handshake_failure without it).
jlink \
  --add-modules java.base,java.desktop,java.logging,java.net.http,java.scripting,jdk.crypto.ec,jdk.dynalink,jdk.unsupported \
  --strip-debug --no-header-files --no-man-pages --compress=2 \
  --output "$APP/extractor/runtime"

cat > "$APPDIR/usr/share/applications/idris.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Idris
Comment=Your mantras and calm music, from your own YouTube playlists
Exec=idris
Icon=idris
Categories=AudioVideo;Audio;Player;
StartupWMClass=com.isg32.idris
Terminal=false
EOF
cp assets/icon/icon.png "$APPDIR/usr/share/icons/hicolor/256x256/apps/idris.png"

cat > "$APPDIR/AppRun" <<'EOF'
#!/bin/sh
# Idris's AppImage entry point: its own libraries first, then the app.
HERE="$(dirname "$(readlink -f "$0")")"
export LD_LIBRARY_PATH="$HERE/usr/lib:$HERE/usr/lib/idris/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$HERE/usr/lib/idris/idris" "$@"
EOF
chmod +x "$APPDIR/AppRun"

echo "== linuxdeploy"
mkdir -p "$TOOLS"
LINUXDEPLOY="$TOOLS/linuxdeploy-x86_64.AppImage"
if [ ! -x "$LINUXDEPLOY" ]; then
  curl -fsSL -o "$LINUXDEPLOY" \
    https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage
  chmod +x "$LINUXDEPLOY"
fi

# media_kit opens libmpv itself (dlopen), so it has to be named.
LIBMPV="$(ldconfig -p | awk '/libmpv\.so\.2 /{print $NF; exit}')"
if [ -z "$LIBMPV" ]; then
  echo "libmpv.so.2 not found: install libmpv (libmpv-dev on Debian/Ubuntu)" >&2
  exit 1
fi

# What every desktop Linux has, and what must match the running system.
EXCLUDE=()
for lib in 'libgtk-3.so*' 'libgdk-3.so*' 'libglib-2.0.so*' 'libgobject-2.0.so*' \
           'libgio-2.0.so*' 'libgmodule-2.0.so*' 'libpango*.so*' 'libcairo*.so*' \
           'libgdk_pixbuf-2.0.so*' 'libatk*.so*' 'libepoxy.so*' 'libwayland-*.so*' \
           'libxkbcommon*.so*' 'libharfbuzz*.so*' 'libfreetype.so*' 'libfontconfig.so*' \
           'libpulse*.so*' 'libasound.so*' 'libpipewire*.so*' 'libjack.so*' \
           'libva*.so*' 'libvdpau.so*' 'libdrm*.so*' 'libvulkan.so*' 'libEGL*.so*' \
           'libGL*.so*' 'libgbm.so*' 'libX*.so*' 'libxcb*.so*' 'libdbus-1.so*' \
           'libsystemd.so*' 'libudev.so*'; do
  EXCLUDE+=(--exclude-library "$lib")
done

rm -f "$OUT"/Idris*.AppImage
(
  cd "$OUT"
  APPIMAGE_EXTRACT_AND_RUN=1 ARCH=x86_64 LDAI_OUTPUT=Idris-x86_64.AppImage \
    "$LINUXDEPLOY" --appdir "$APPDIR" \
      --executable "$APP/idris" \
      --library "$LIBMPV" \
      --desktop-file "$APPDIR/usr/share/applications/idris.desktop" \
      --icon-file "$APPDIR/usr/share/icons/hicolor/256x256/apps/idris.png" \
      --custom-apprun "$APPDIR/AppRun" \
      "${EXCLUDE[@]}" \
      --output appimage
)

echo "Done: $OUT/Idris-x86_64.AppImage ($(du -h "$OUT/Idris-x86_64.AppImage" | cut -f1))"
