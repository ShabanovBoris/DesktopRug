# Security

Security fixes target the latest release and the `main` branch. Older versions are not maintained separately.

Please report vulnerabilities privately through [GitHub's vulnerability reporting](https://github.com/ShabanovBoris/DesktopRug/security/advisories/new). Include the affected version, macOS version, reproduction steps, and impact. Do not publish private files, credentials, or sensitive Finder diagnostics in an issue.

The app reads Finder metadata only after Automation access is granted. It does not contain a network client, move desktop files, or request Accessibility/Screen Recording permission. Release binaries currently use ad-hoc signing and are not notarized; the source and archive checksums are available for review.

For ordinary bugs, use the public issue tracker.
