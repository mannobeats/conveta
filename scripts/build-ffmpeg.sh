#!/bin/zsh
# Builds the FFmpeg helper Conveta bundles for formats Apple's frameworks can't write
# (MP3, MKV, WebM, Ogg Vorbis, WMA, WebP...).
#
# License: LGPL only. No --enable-gpl, no --enable-nonfree, no x264/x265/fdk-aac.
# Every dependency is LGPL or BSD. H.264/HEVC/ProRes encoding uses Apple's VideoToolbox.
# Everything is linked statically; the result depends on system frameworks only.
#
# Output: Vendor/FFmpeg/bin/{ffmpeg,ffprobe} and Vendor/FFmpeg/BUILDINFO.txt
# Usage:  scripts/build-ffmpeg.sh            (arm64)
set -euo pipefail
cd "${0:A:h}/.."

FFMPEG=9.0.2
LAME=3.100
OPUS=1.5.2
OGG=1.3.5
VORBIS=1.3.7
VPX=1.15.2
WEBP=1.6.0
DAV1D=1.5.2

ARCH=arm64
MIN_OS=26.0
JOBS=$(sysctl -n hw.ncpu)
WORK=~/Library/Developer/Conveta/ffmpeg-build
SRC=$WORK/src
PREFIX=$WORK/prefix-$ARCH
OUT=$PWD/Vendor/FFmpeg
CHECKSUMS=$PWD/Vendor/FFmpeg/sources.sha256

mkdir -p $SRC $PREFIX $OUT/bin
export CFLAGS="-arch $ARCH -mmacosx-version-min=$MIN_OS -O3"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="-arch $ARCH -mmacosx-version-min=$MIN_OS"
export MACOSX_DEPLOYMENT_TARGET=$MIN_OS
# Only our prefix: never pick up Homebrew's (often GPL or dynamic) libraries.
export PKG_CONFIG_LIBDIR=$PREFIX/lib/pkgconfig
export PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig

fetch() { # url name
  local file=$SRC/$2
  [[ -f $file ]] || curl -fsSL "$1" -o "$file"
  local sum=$(shasum -a 256 "$file" | cut -d' ' -f1)
  if [[ -f $CHECKSUMS ]] && grep -q " $2\$" $CHECKSUMS; then
    grep -q "^$sum  $2\$" $CHECKSUMS || { echo "Checksum mismatch for $2"; exit 1; }
  else
    echo "$sum  $2" >> $CHECKSUMS
  fi
}

unpack() { # archive dir
  rm -rf $SRC/$2
  mkdir -p $SRC/$2
  tar -xf $SRC/$1 -C $SRC/$2 --strip-components 1
}

step() { echo "==> $1"; }
# Skips a dependency whose library is already installed in the prefix (delete $WORK to rebuild all).
built() { [[ -f $PREFIX/lib/$1 ]] && echo "    already built" ; }

step "Downloading sources"
fetch https://ffmpeg.org/releases/ffmpeg-$FFMPEG.tar.xz ffmpeg-$FFMPEG.tar.xz
fetch https://downloads.sourceforge.net/project/lame/lame/$LAME/lame-$LAME.tar.gz lame-$LAME.tar.gz
fetch https://downloads.xiph.org/releases/opus/opus-$OPUS.tar.gz opus-$OPUS.tar.gz
fetch https://downloads.xiph.org/releases/ogg/libogg-$OGG.tar.xz libogg-$OGG.tar.xz
fetch https://downloads.xiph.org/releases/vorbis/libvorbis-$VORBIS.tar.xz libvorbis-$VORBIS.tar.xz
fetch https://github.com/webmproject/libvpx/archive/refs/tags/v$VPX.tar.gz libvpx-$VPX.tar.gz
fetch https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-$WEBP.tar.gz libwebp-$WEBP.tar.gz
fetch https://code.videolan.org/videolan/dav1d/-/archive/$DAV1D/dav1d-$DAV1D.tar.gz dav1d-$DAV1D.tar.gz

autotools() { # dir, extra configure args...
  local dir=$1; shift
  (cd $SRC/$dir && ./configure --prefix=$PREFIX --host=aarch64-apple-darwin --disable-shared --enable-static "$@" >/dev/null \
     && make -j$JOBS >/dev/null && make install >/dev/null)
}

step "LAME (MP3, LGPL)"
if ! built libmp3lame.a; then
unpack lame-$LAME.tar.gz lame
sed -i '' '/lame_init_old/d' $SRC/lame/include/libmp3lame.sym   # symbol missing in 3.100
autotools lame --disable-frontend --disable-decoder
fi

step "Ogg, Vorbis, Opus (BSD)"
if ! built libopus.a; then
unpack libogg-$OGG.tar.xz ogg
autotools ogg
unpack libvorbis-$VORBIS.tar.xz vorbis
sed -i '' 's/-force_cpusubtype_ALL//g' $SRC/vorbis/configure   # flag the modern linker rejects
autotools vorbis --disable-oggtest --disable-docs --disable-examples
unpack opus-$OPUS.tar.gz opus
autotools opus --disable-doc --disable-extra-programs
fi

step "libvpx: VP8/VP9 (BSD)"
if ! built libvpx.a; then
unpack libvpx-$VPX.tar.gz vpx
VPX_TARGET=$( (cd $SRC/vpx && ./configure --help || true) | grep -oE 'arm64-darwin[0-9]+-gcc' | sort -V | tail -1)
(cd $SRC/vpx && ./configure --prefix=$PREFIX --target=$VPX_TARGET --disable-shared --enable-static --enable-pic \
   --disable-examples --disable-tools --disable-docs --disable-unit-tests --enable-vp9-highbitdepth >/dev/null \
   && make -j$JOBS >/dev/null && make install >/dev/null)
fi

step "libwebp (BSD)"
if ! built libwebp.a; then
unpack libwebp-$WEBP.tar.gz webp
autotools webp --disable-gl --disable-sdl --disable-png --disable-jpeg --disable-tiff --disable-gif \
  --enable-libwebpmux --enable-libwebpdemux
fi

step "dav1d: AV1 decoding (BSD)"
if ! built libdav1d.a; then
unpack dav1d-$DAV1D.tar.gz dav1d
(cd $SRC/dav1d && meson setup build --prefix=$PREFIX --libdir=lib --default-library=static --buildtype=release \
   -Denable_tools=false -Denable_tests=false -Dc_args="$CFLAGS" -Dc_link_args="$LDFLAGS" >/dev/null \
   && ninja -C build >/dev/null && ninja -C build install >/dev/null)
fi

step "FFmpeg $FFMPEG (LGPL)"
unpack ffmpeg-$FFMPEG.tar.xz ffmpeg
(cd $SRC/ffmpeg && ./configure --prefix=$PREFIX --arch=$ARCH --cc=clang \
   --extra-cflags="$CFLAGS -I$PREFIX/include" --extra-ldflags="$LDFLAGS -L$PREFIX/lib" --extra-libs=-liconv \
   --pkg-config-flags=--static \
   --disable-gpl --disable-nonfree --disable-autodetect \
   --enable-static --disable-shared --disable-doc --disable-ffplay --disable-network --disable-debug \
   --enable-videotoolbox --enable-audiotoolbox --enable-zlib --enable-bzlib --enable-iconv \
   --enable-libmp3lame --enable-libopus --enable-libvorbis --enable-libvpx --enable-libwebp --enable-libdav1d \
   > $WORK/ffmpeg-configure.log \
   && make -j$JOBS >/dev/null && make install >/dev/null)

step "Checking the result"
for tool in ffmpeg ffprobe; do
  cp $PREFIX/bin/$tool $OUT/bin/$tool
  strip -x $OUT/bin/$tool
  if otool -L $OUT/bin/$tool | tail -n +2 | grep -vE '^\s+/(System/Library|usr/lib)/'; then
    echo "$tool links a non-system library"; exit 1
  fi
done
$OUT/bin/ffmpeg -hide_banner -version | head -1
grep -q -- "--disable-gpl" <($OUT/bin/ffmpeg -hide_banner -buildconf) || { echo "Not an LGPL build"; exit 1; }
if $OUT/bin/ffmpeg -hide_banner -L | grep -q "GNU General Public License"; then echo "GPL build"; exit 1; fi

{
  echo "FFmpeg $FFMPEG, LGPL 2.1 or later, static, $ARCH, macOS $MIN_OS+"
  echo "LAME $LAME (LGPL), Opus $OPUS, libogg $OGG, libvorbis $VORBIS, libvpx $VPX, libwebp $WEBP, dav1d $DAV1D (BSD)"
  echo "Built $(date -u +%Y-%m-%d) with scripts/build-ffmpeg.sh"
  echo
  $OUT/bin/ffmpeg -hide_banner -buildconf
} > $OUT/BUILDINFO.txt
echo "Done: $OUT/bin"
