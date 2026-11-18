# Contributing to Conveta

Thanks for helping. A few things keep the project healthy.

## Getting set up

Follow "Build from source" in the README. `scripts/test.sh` must pass before you open a pull request,
and the build must have zero warnings (the build script fails on any).

## What a good change looks like

- **One change per pull request**, with a clear title and a sentence on why.
- **Tests for behaviour.** Engine work goes in `Packages/ConvetaKit` with tests that run on real
  media (see `Fixtures.swift`; tests create their own files, so the repository holds none). App
  behaviour goes in the self-test (`App/Integration/SelfTest.swift`).
- **Native and calm.** Conveta follows the macOS Human Interface Guidelines: standard controls,
  menus with shortcuts, light and dark mode, no purple. Look at your change in both modes.
- **Licensing.** Code must be MIT-compatible. Never add GPL code or enable GPL parts of FFmpeg
  (`--enable-gpl`, x264, x265); `scripts/build-ffmpeg.sh` refuses to produce such a build.

## Reporting bugs

Open an issue with the bug template. For a conversion bug, include the source file's details
(Conveta shows them under the file name) or a short sample file. For a download bug, include the
link if it's public.

## Security

Please report vulnerabilities privately; see [SECURITY.md](SECURITY.md).
