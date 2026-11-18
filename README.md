# Conveta

A native Mac app that converts video, audio, images and PDFs — one file or a thousand — using
the Mac's own hardware encoders. Drop files in, right-click them in Finder, or run it from Shortcuts.

## What it converts

| From | To |
| --- | --- |
| Video (MOV, MP4, MKV, WebM, AVI, WMV, FLV, MPEG-TS, 3GP, VP9, AV1…) | MP4, MOV, M4V, MKV (H.264, HEVC, ProRes, or stream copy), WebM (VP9), AVI, animated GIF, or audio only |
| Audio (MP3, WAV, M4A, AAC, FLAC, Ogg, Opus, WMA, AIFF, APE, AMR…) | MP3, M4A (AAC or Apple Lossless), AAC, WAV, AIFF, FLAC, Ogg Vorbis, Opus, WMA |
| Images (HEIC, PNG, JPEG, WebP, AVIF, TIFF, RAW, PSD, GIF…) | JPEG, PNG, HEIC, AVIF, WebP (still or animated), TIFF, GIF, BMP, PDF |
| PDF | One image per page (PNG, JPEG, HEIC, TIFF) |

Two engines, picked per file:

- **Apple frameworks** (AVFoundation, VideoToolbox, Core Audio, ImageIO) whenever they can read the
  source and write the format: fastest, hardware accelerated. Opus is written as standard Ogg Opus
  by a small muxer in `ConvetaKit`.
- **A bundled FFmpeg helper** for everything else (MP3, MKV, WebM, Ogg, WMA, WebP, and sources such as
  MKV or WMA). It is an LGPL-only build — no `--enable-gpl`, no x264 — with LAME, Opus, Vorbis, libvpx,
  libwebp and dav1d, linked statically, signed to run inside the app's sandbox. H.264 and HEVC still
  go through VideoToolbox. Lossy audio is never re-encoded above the source's bitrate.

## Ways in

- **Window:** drag files or folders in, pick a format per kind in the inspector, press Convert (⌘↩).
- **Finder:** right-click → *Convert with Conveta* → format. Turn it on once in Settings → Finder.
- **Services:** *Add to Conveta* in any app's Services menu.
- **Shortcuts:** *Convert Files* and *Add Files to Conveta* actions; usable as Finder Quick Actions.
- **URLs:** `conveta://action/convert`, `/stop`, `/add`, `/clear`.

## Build and test

Requires Xcode 26+, macOS 26+, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
scripts/build-ffmpeg.sh   # once: builds the LGPL FFmpeg helper into Vendor/FFmpeg (pinned, checksummed)
scripts/build.sh --open   # generate the project, build with zero warnings, install to ~/Applications, launch
scripts/test.sh           # ConvetaKit tests + the app's sandboxed self-test (Conveta --selftest)
```

FFmpeg is licensed under the LGPL 2.1 or later; `Vendor/FFmpeg/BUILDINFO.txt` records the exact
configuration and `scripts/build-ffmpeg.sh` rebuilds it from source.

## Layout

```
Packages/ConvetaKit/   formats, probing, converters, output naming, Finder hand-off (no UI, fully tested)
App/                   SwiftUI app: model (queue, preferences, folder access), views, integrations
FinderExtension/       Finder Sync extension: the right-click menu
Shared/                code both targets use (app group)
Icon/AppIcon.icon      Icon Composer source for the app icon
```

## License

MIT. See [LICENSE](LICENSE).
