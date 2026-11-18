# Third-party software

Conveta's own code is MIT licensed. It includes or uses:

| Component | License | How it's used |
| --- | --- | --- |
| [FFmpeg](https://ffmpeg.org) 9.0.2 | LGPL 2.1 or later | Bundled helper executables (`Contents/Helpers`), built without GPL parts by `scripts/build-ffmpeg.sh`; exact configuration in `Vendor/FFmpeg/BUILDINFO.txt` |
| [LAME](https://lame.sourceforge.io) 3.100 | LGPL | MP3 encoding, inside the FFmpeg helper |
| [libvpx](https://chromium.googlesource.com/webm/libvpx) 1.15.2 | BSD 3-Clause | VP8/VP9, inside the FFmpeg helper |
| [libwebp](https://chromium.googlesource.com/webm/libwebp) 1.6.0 | BSD 3-Clause | WebP, inside the FFmpeg helper |
| [Opus](https://opus-codec.org) 1.5.2 | BSD 3-Clause | Opus, inside the FFmpeg helper |
| [libogg](https://xiph.org/ogg/) 1.3.5, [libvorbis](https://xiph.org/vorbis/) 1.3.7 | BSD 3-Clause | Ogg Vorbis, inside the FFmpeg helper |
| [dav1d](https://code.videolan.org/videolan/dav1d) 1.5.2 | BSD 2-Clause | AV1 decoding, inside the FFmpeg helper |
| [Sparkle](https://sparkle-project.org) 2.10.1 | MIT | Software updates |
| [yt-dlp](https://github.com/yt-dlp/yt-dlp) | Unlicense | Downloads; not bundled, installed on first use from its official release |

The FFmpeg helper is a separate program that Conveta runs; you can replace it with your own LGPL
build of the same version using `scripts/build-ffmpeg.sh`. The source for every component is linked
above, and the exact versions are pinned with checksums in `Vendor/FFmpeg/sources.sha256`.
