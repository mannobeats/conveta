<div align="center">

# Conveta

**Convert anything. Download from anywhere. Native on the Mac.**

Video, audio, images and PDFs, one file or a thousand, plus downloads from YouTube, Instagram,
TikTok and over a thousand other sites. Free and open source.

[Download for macOS](https://github.com/mannobeats/conveta/releases/latest) · macOS 26 or later · Apple silicon and Intel

</div>

## What it does

- **Convert** between every common format:
  - Video: MP4, MOV, M4V, MKV, WebM, AVI, animated GIF
  - Audio: MP3, M4A (AAC, Apple Lossless), AAC, WAV, AIFF, FLAC, Ogg Vorbis, Opus, WMA
  - Images: JPEG, PNG, HEIC, AVIF, WebP, TIFF, GIF, BMP, PDF
  - PDF pages to images
  - Reads far more: MKV, WebM, FLV, WMV, WMA, APE, AMR, VP9, AV1, RAW, PSD and others.
- **Download** a video, a playlist or a whole channel. Choose from every resolution on offer (with
  sizes), several at once. Subtitles can be embedded or saved as `.srt`. 1440p and 4K arrive as HEVC,
  so they play in QuickTime.
- **Presets:** Discord (10 MB), Email, WhatsApp, Instagram & TikTok, Podcast, Lossless, Web Images,
  or save your own.
- **Fit a size:** make any video fit 8, 10, 25 or more megabytes.
- **Trim** videos and recordings before converting.
- **Fast:** the Mac's media engine for H.264, HEVC and ProRes; Apple's own frameworks first, a
  bundled FFmpeg for the rest.
- **Everywhere on the Mac:** drag and drop, ⌘L for links, right-click in Finder, the Services menu,
  Shortcuts actions and `conveta://` links.
- **Stays current:** updates itself with [Sparkle](https://sparkle-project.org).

## Install

Download the latest `.dmg` from [Releases](https://github.com/mannobeats/conveta/releases/latest)
and drag Conveta to Applications. Builds are signed with Developer ID and notarized by Apple.

To get the right-click menu, open Conveta → Settings → Finder → Turn On.

## Build from source

Needs Xcode 26 or later, macOS 26 or later, and Homebrew.

```bash
brew install xcodegen nasm cmake pkgconf meson ninja autoconf automake
scripts/build-ffmpeg.sh          # once: builds the LGPL FFmpeg helper (universal), pinned and checksummed
scripts/build.sh --open          # builds with zero warnings, installs to ~/Applications, launches
scripts/test.sh                  # 90+ tests on real media, then the app's own self-test
CONVETA_NETWORK_TESTS=1 scripts/test.sh   # also real downloads
```

To sign with your own team, change `DEVELOPMENT_TEAM` and the bundle identifiers in `project.yml`.

## How it's built

```
Packages/ConvetaKit/   the engine: formats, probing, converters, FFmpeg and yt-dlp, presets (no UI, fully tested)
App/                   SwiftUI app: queue, inspector, link sheet, settings, integrations
FinderExtension/       the right-click menu (Finder Sync)
Shared/                code both targets use
Icon/AppIcon.icon      the icon, as an Icon Composer document
scripts/               build, test, FFmpeg and release scripts
.github/workflows/     CI on every push; signed, notarized releases on every tag
```

Conveta picks an engine per file. Apple's frameworks (AVFoundation, VideoToolbox, Core Audio,
ImageIO) handle everything they can read and write. A bundled **LGPL-only** FFmpeg helper handles
the rest. Downloads use [yt-dlp](https://github.com/yt-dlp/yt-dlp), which Conveta installs on first
use from its official release, verifies against the published SHA-256 list, and keeps up to date.

## Contributing

Issues and pull requests are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md). The
[roadmap](https://github.com/mannobeats/conveta/issues?q=is%3Aissue+is%3Aopen+label%3Aroadmap)
lists what's planned.

## Responsible use

Download only content you own or have permission to use, and respect each site's terms.

## License

Conveta is [MIT licensed](LICENSE). It uses FFmpeg (LGPL 2.1+), LAME (LGPL), libvpx, libwebp, Opus,
Vorbis and dav1d (BSD), Sparkle (MIT) and yt-dlp (Unlicense). See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
