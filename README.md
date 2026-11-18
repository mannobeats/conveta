# Conveta

A native Mac app that converts video, audio, images and PDFs — one file or a thousand — using
the Mac's own hardware encoders. Drop files in, right-click them in Finder, or run it from Shortcuts.

## What it converts

| From | To |
| --- | --- |
| Video (MOV, MP4, M4V, AVI, MPEG-TS, 3GP…) | MP4, MOV, M4V (H.264, HEVC, ProRes 422/4444, or stream copy), animated GIF, or audio only |
| Audio (WAV, MP3, M4A, AIFF, FLAC, CAF…) | M4A (AAC or Apple Lossless), WAV, AIFF, FLAC, Opus |
| Images (HEIC, PNG, JPEG, WebP, TIFF, RAW, PSD, GIF…) | JPEG, PNG, HEIC, AVIF, TIFF, GIF, BMP, PDF |
| PDF | One image per page (PNG, JPEG, HEIC, TIFF) |

Everything runs on Apple frameworks (AVFoundation, VideoToolbox, Core Audio, ImageIO), so the app
is small, sandboxed, fast on Apple silicon, and has no GPL dependencies. Opus is written as
standard Ogg Opus by a small muxer in `ConvetaKit`.

## Ways in

- **Window:** drag files or folders in, pick a format per kind in the inspector, press Convert (⌘↩).
- **Finder:** right-click → *Convert with Conveta* → format. Turn it on once in Settings → Finder.
- **Services:** *Add to Conveta* in any app's Services menu.
- **Shortcuts:** *Convert Files* and *Add Files to Conveta* actions; usable as Finder Quick Actions.
- **URLs:** `conveta://action/convert`, `/stop`, `/add`, `/clear`.

## Build and test

Requires Xcode 26+, macOS 26+, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
scripts/build.sh --open   # generate the project, build with zero warnings, install to ~/Applications, launch
scripts/test.sh           # ConvetaKit tests + the app's sandboxed self-test (Conveta --selftest)
```

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
