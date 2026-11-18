# Releasing Conveta

A release is a version tag. Pushing `v1.2.0` runs `.github/workflows/release.yml`, which builds a
universal app, signs it with Developer ID, notarizes and staples it, packs a signed DMG, signs the
update for Sparkle, and publishes a GitHub release with the DMG and `appcast.xml`. Installed copies
find the update through `https://github.com/mannobeats/conveta/releases/latest/download/appcast.xml`.

```bash
git tag v1.2.0 && git push origin v1.2.0
```

## One-time setup

Two scripts give the repository what the Release workflow needs. Run them yourself, on the Mac
with your Developer ID certificate. Passwords are typed at hidden prompts; every value goes straight
into GitHub's encrypted secrets and nothing is printed, logged, written to disk or committed.

```bash
scripts/setup-release-secrets.sh                        # explains how to export the certificate
scripts/setup-release-secrets.sh ~/Desktop/DeveloperID.p12
scripts/setup-update-key.sh                             # only if SPARKLE_PRIVATE_KEY isn't set yet
```

| Secret | What it is |
| --- | --- |
| `APPLE_CERTIFICATE`, `APPLE_CERTIFICATE_PASSWORD` | Your Developer ID Application certificate (`.p12`, base64) and its export password |
| `APPLE_SIGNING_IDENTITY` | The certificate's name, read from your keychain |
| `APPLE_ID`, `APPLE_PASSWORD`, `APPLE_TEAM_ID` | Your Apple Account email, an app-specific password (account.apple.com → Sign-In and Security → App-Specific Passwords), and your team ID, read from the certificate. The script checks them with Apple before saving. |
| `SPARKLE_PRIVATE_KEY` | The EdDSA key that signs updates. Its public half is `SUPublicEDKey` in `App/Resources/Info.plist`; the key itself stays in your login keychain (account `conveta`). Back it up: without it, installed copies can't verify new updates. |

Delete the exported `.p12` afterwards; GitHub keeps its own encrypted copy.

## Releasing from a Mac instead

```bash
export APPLE_ID=… APPLE_TEAM_ID=…
read -rs APPLE_PASSWORD && export APPLE_PASSWORD     # hidden, not in shell history
scripts/release.sh 1.2.0                             # build/release/Conveta-1.2.0.dmg and appcast.xml
gh release create v1.2.0 build/release/Conveta-1.2.0.dmg build/release/appcast.xml --generate-notes
```

`SKIP_NOTARIZE=1 scripts/release.sh 1.2.0` runs everything except Apple's notary service, to check
a release build without publishing.

## Keeping personal information out

`scripts/check-leaks.sh` fails on home folder paths, disk and computer names, local network domains
and e-mail addresses in tracked files; CI runs it on every push, and `scripts/release.sh` runs it on
the built app before packaging. FFmpeg is built in `/Users/Shared/ConvetaFFmpegBuild` because it
records its build paths inside the binary.
