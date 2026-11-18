# Releasing Conveta

A release is a version tag. Pushing `v1.2.0` runs `.github/workflows/release.yml`, which builds a
universal app, signs it with Developer ID, notarizes and staples it, packs a signed DMG, signs the
update for Sparkle, and publishes a GitHub release with the DMG and `appcast.xml`. Installed copies
find the update through `https://github.com/mannobeats/conveta/releases/latest/download/appcast.xml`.

```bash
git tag v1.2.0 && git push origin v1.2.0
```

## One-time setup: repository secrets

Settings → Secrets and variables → Actions:

| Secret | What it is | How to get it |
| --- | --- | --- |
| `DEVELOPER_ID_CERTIFICATE_P12` | Your Developer ID Application certificate with its private key, base64 | Keychain Access → My Certificates → right-click "Developer ID Application: …" → Export → `.p12`; then `base64 -i cert.p12 \| pbcopy` |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | The password you chose when exporting | |
| `NOTARY_KEY_P8` | App Store Connect API key, base64 | App Store Connect → Users and Access → Integrations → App Store Connect API → Team Keys → + (Developer access) → download `AuthKey_XXXX.p8`; `base64 -i AuthKey_XXXX.p8 \| pbcopy` |
| `NOTARY_KEY_ID` | The key's ID | Shown next to the key |
| `NOTARY_ISSUER_ID` | Your issuer ID | Shown above the keys list |
| `SPARKLE_PRIVATE_KEY` | The EdDSA key that signs updates | Already set. Its public half is `SUPublicEDKey` in `App/Resources/Info.plist`; the key also lives in the release Mac's login keychain (account `conveta`). Never lose it: without it, installed copies can't verify new updates. |

## Releasing from a Mac instead

```bash
xcrun notarytool store-credentials conveta   # once
scripts/release.sh 1.2.0                     # build/release/Conveta-1.2.0.dmg and appcast.xml
gh release create v1.2.0 build/release/Conveta-1.2.0.dmg build/release/appcast.xml --generate-notes
```

`SKIP_NOTARIZE=1 scripts/release.sh 1.2.0` runs everything except Apple's notary service, to check
a release build without publishing.
