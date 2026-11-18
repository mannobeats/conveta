# Security

Please report vulnerabilities privately through
[GitHub's private vulnerability reporting](https://github.com/mannobeats/conveta/security/advisories/new),
not in public issues. You'll get a reply within a week.

Releases are signed with Developer ID, notarized by Apple, and updates are verified with an EdDSA
signature (Sparkle) before they install. The download engine (yt-dlp) is fetched from its official
GitHub release and checked against the release's published SHA-256 list.
