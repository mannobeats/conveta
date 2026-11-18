# Conveta

A native Mac app that converts video, audio, images and PDFs — one file or a thousand — using
the Mac's own hardware encoders, and downloads videos from YouTube, Instagram, TikTok and other sites.
Drop files in, paste a link, right-click files in Finder, or run it from Shortcuts.

Conveta is distributed directly (Developer ID, notarized), not through the Mac App Store, whose
rules don't allow downloading from third-party sites.

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

## Downloads

Paste a link (⌘L, or ⌘V in the window, or drag it from the browser) and pick any format: MP4,
MP3, GIF and the rest. Downloads use [yt-dlp](https://github.com/yt-dlp/yt-dlp) (public domain),
which Conveta installs on first use from its official release, verifies against the release's
SHA-256 list, and updates every few days. Video arrives as H.264/AAC MP4 when the site offers it,
so MP4 downloads need no re-encoding. For posts that need an account, Settings → Downloads can
borrow a browser's sign-in. Download only what you have the right to use.

## Ways in

- **Window:** drag files or folders in, pick a format per kind in the inspector, press Convert (⌘↩).
- **Finder (startup disk):** right-click → *Convert with Conveta* → format. Turn it on once in Settings → Finder.
- **Every disk:** right-click → *Convert to MP3 / MP4 / JPEG / PNG with Conveta* or *Add to Conveta* (Services).
- **Shortcuts:** *Convert Files*, *Add Files to Conveta* and *Download Video* actions.
- **URLs:** `conveta://download?url=…&format=mp3`, `conveta://action/convert`, `/stop`, `/add`, `/link`, `/clear`.

## Build and test

Requires Xcode 26+, macOS 26+, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
scripts/build-ffmpeg.sh   # once: builds the LGPL FFmpeg helper into Vendor/FFmpeg (pinned, checksummed)
scripts/build.sh --open   # generate the project, build with zero warnings, install to ~/Applications, launch
scripts/test.sh           # ConvetaKit tests + the app's self-test (Conveta --selftest)
CONVETA_NETWORK_TESTS=1 scripts/test.sh   # also real downloads and engine install
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
