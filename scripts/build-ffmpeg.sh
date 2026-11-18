#!/bin/zsh
# Builds the FFmpeg helper Conveta bundles for formats Apple's frameworks can't write
# (MP3, MKV, WebM, Ogg Vorbis, WMA, WebP...).
#
# License: LGPL only. No --enable-gpl, no --enable-nonfree, no x264/x265/fdk-aac.
# Every dependency is LGPL or BSD. H.264/HEVC/ProRes encoding uses Apple's VideoToolbox.
# Everything is linked statically; the result depends on system frameworks only.
#
# Output: Vendor/FFmpeg/bin/{ffmpeg,ffprobe} (universal: arm64 + x86_64) and Vendor/FFmpeg/BUILDINFO.txt
# Usage:  scripts/build-ffmpeg.sh                  both architectures, merged with lipo
#         ARCHS=arm64 scripts/build-ffmpeg.sh      one architecture (faster, for development)
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

ARCHS=(${=ARCHS:-arm64 x86_64})
MIN_OS=26.0
JOBS=$(sysctl -n hw.ncpu)
WORK=~/Library/Developer/Conveta/ffmpeg-build
SRC=$WORK/src
OUT=$PWD/Vendor/FFmpeg
CHECKSUMS=$PWD/Vendor/FFmpeg/sources.sha256
mkdir -p $SRC $OUT/bin

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

step() { echo "==> $1"; }

step "Downloading sources"
fetch https://ffmpeg.org/releases/ffmpeg-$FFMPEG.tar.xz ffmpeg-$FFMPEG.tar.xz
fetch https://downloads.sourceforge.net/project/lame/lame/$LAME/lame-$LAME.tar.gz lame-$LAME.tar.gz
fetch https://downloads.xiph.org/releases/opus/opus-$OPUS.tar.gz opus-$OPUS.tar.gz
fetch https://downloads.xiph.org/releases/ogg/libogg-$OGG.tar.xz libogg-$OGG.tar.xz
fetch https://downloads.xiph.org/releases/vorbis/libvorbis-$VORBIS.tar.xz libvorbis-$VORBIS.tar.xz
fetch https://github.com/webmproject/libvpx/archive/refs/tags/v$VPX.tar.gz libvpx-$VPX.tar.gz
fetch https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-$WEBP.tar.gz libwebp-$WEBP.tar.gz
fetch https://code.videolan.org/videolan/dav1d/-/archive/$DAV1D/dav1d-$DAV1D.tar.gz dav1d-$DAV1D.tar.gz

build_arch() { # arm64 | x86_64
  local ARCH=$1
  local BUILD=$WORK/build-$ARCH PREFIX=$WORK/prefix-$ARCH
  local HOST=$([[ $ARCH == arm64 ]] && echo aarch64-apple-darwin || echo x86_64-apple-darwin)
  local CPU=$([[ $ARCH == arm64 ]] && echo aarch64 || echo x86_64)
  mkdir -p $BUILD $PREFIX
  export CFLAGS="-arch $ARCH -mmacosx-version-min=$MIN_OS -O3"
  export CXXFLAGS="$CFLAGS"
  export LDFLAGS="-arch $ARCH -mmacosx-version-min=$MIN_OS"
  export MACOSX_DEPLOYMENT_TARGET=$MIN_OS
  # Only our prefix: never pick up Homebrew's (often GPL or dynamic) libraries.
  export PKG_CONFIG_LIBDIR=$PREFIX/lib/pkgconfig
  export PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig

  unpack() { rm -rf $BUILD/$2; mkdir -p $BUILD/$2; tar -xf $SRC/$1 -C $BUILD/$2 --strip-components 1; }
  built() { [[ -f $PREFIX/lib/$1 ]] && echo "    already built"; }
  autotools() {
    local dir=$1; shift
    (cd $BUILD/$dir && ./configure --prefix=$PREFIX --host=$HOST --disable-shared --enable-static "$@" >/dev/null \
       && make -j$JOBS >/dev/null && make install >/dev/null)
  }

  step "[$ARCH] LAME (MP3, LGPL)"
  if ! built libmp3lame.a; then
    unpack lame-$LAME.tar.gz lame
    sed -i '' '/lame_init_old/d' $BUILD/lame/include/libmp3lame.sym   # symbol missing in 3.100
    autotools lame --disable-frontend --disable-decoder
  fi

  step "[$ARCH] Ogg, Vorbis, Opus (BSD)"
  if ! built libopus.a; then
    unpack libogg-$OGG.tar.xz ogg
    autotools ogg
    unpack libvorbis-$VORBIS.tar.xz vorbis
    sed -i '' 's/-force_cpusubtype_ALL//g' $BUILD/vorbis/configure   # flag the modern linker rejects
    autotools vorbis --disable-oggtest --disable-docs --disable-examples
    unpack opus-$OPUS.tar.gz opus
    autotools opus --disable-doc --disable-extra-programs
  fi

  step "[$ARCH] libvpx: VP8/VP9 (BSD)"
  if ! built libvpx.a; then
    unpack libvpx-$VPX.tar.gz vpx
    local family=$([[ $ARCH == arm64 ]] && echo arm64 || echo x86_64)
    local target=$( (cd $BUILD/vpx && ./configure --help || true) | grep -oE "$family-darwin[0-9]+-gcc" | sort -V | tail -1)
    (cd $BUILD/vpx && ./configure --prefix=$PREFIX --target=$target --disable-shared --enable-static --enable-pic \
       --disable-examples --disable-tools --disable-docs --disable-unit-tests --enable-vp9-highbitdepth >/dev/null \
       && make -j$JOBS >/dev/null && make install >/dev/null)
  fi

  step "[$ARCH] libwebp (BSD)"
  if ! built libwebp.a; then
    unpack libwebp-$WEBP.tar.gz webp
    autotools webp --disable-gl --disable-sdl --disable-png --disable-jpeg --disable-tiff --disable-gif \
      --enable-libwebpmux --enable-libwebpdemux
  fi

  step "[$ARCH] dav1d: AV1 decoding (BSD)"
  if ! built libdav1d.a; then
    unpack dav1d-$DAV1D.tar.gz dav1d
    cat > $BUILD/dav1d-cross.txt <<CROSS
[binaries]
c = 'clang'
strip = 'strip'
[built-in options]
c_args = ['-arch', '$ARCH', '-mmacosx-version-min=$MIN_OS']
c_link_args = ['-arch', '$ARCH', '-mmacosx-version-min=$MIN_OS']
[host_machine]
system = 'darwin'
cpu_family = '$CPU'
cpu = '$CPU'
endian = 'little'
CROSS
    (cd $BUILD/dav1d && meson setup build --cross-file $BUILD/dav1d-cross.txt --prefix=$PREFIX --libdir=lib \
       --default-library=static --buildtype=release -Denable_tools=false -Denable_tests=false >/dev/null \
       && ninja -C build >/dev/null && ninja -C build install >/dev/null)
  fi

  step "[$ARCH] FFmpeg $FFMPEG (LGPL)"
  if [[ ! -x $PREFIX/bin/ffmpeg ]]; then
    unpack ffmpeg-$FFMPEG.tar.xz ffmpeg
    (cd $BUILD/ffmpeg && ./configure --prefix=$PREFIX --arch=$ARCH --target-os=darwin --enable-cross-compile --cc=clang \
       --extra-cflags="$CFLAGS -I$PREFIX/include" --extra-ldflags="$LDFLAGS -L$PREFIX/lib" --extra-libs=-liconv \
       --pkg-config-flags=--static \
       --disable-gpl --disable-nonfree --disable-autodetect \
       --enable-static --disable-shared --disable-doc --disable-ffplay --disable-network --disable-debug \
       --enable-videotoolbox --enable-audiotoolbox --enable-zlib --enable-bzlib --enable-iconv \
       --enable-libmp3lame --enable-libopus --enable-libvorbis --enable-libvpx --enable-libwebp --enable-libdav1d \
       > $WORK/ffmpeg-configure-$ARCH.log \
       && make -j$JOBS >/dev/null && make install >/dev/null)
  fi
}

for arch in $ARCHS; do build_arch $arch; done

step "Merging and checking"
for tool in ffmpeg ffprobe; do
  lipo -create $(for arch in $ARCHS; do echo $WORK/prefix-$arch/bin/$tool; done) -output $OUT/bin/$tool
  strip -x $OUT/bin/$tool
  # Only dependency lines (indented); a universal binary also prints one header per architecture.
  if otool -L $OUT/bin/$tool | grep -E '^\s' | grep -vE '^\s+/(System/Library|usr/lib)/'; then
    echo "$tool links a non-system library"; exit 1
  fi
done
lipo -info $OUT/bin/ffmpeg
$OUT/bin/ffmpeg -hide_banner -version | head -1
grep -q -- "--disable-gpl" <($OUT/bin/ffmpeg -hide_banner -buildconf) || { echo "Not an LGPL build"; exit 1; }
if $OUT/bin/ffmpeg -hide_banner -L | grep -q "GNU General Public License"; then echo "GPL build"; exit 1; fi

{
  echo "FFmpeg $FFMPEG, LGPL 2.1 or later, static, ${ARCHS[*]}, macOS $MIN_OS+"
  echo "LAME $LAME (LGPL), Opus $OPUS, libogg $OGG, libvorbis $VORBIS, libvpx $VPX, libwebp $WEBP, dav1d $DAV1D (BSD)"
  echo "Built $(date -u +%Y-%m-%d) with scripts/build-ffmpeg.sh"
  echo
  $OUT/bin/ffmpeg -hide_banner -buildconf
} > $OUT/BUILDINFO.txt
echo "Done: $OUT/bin"
