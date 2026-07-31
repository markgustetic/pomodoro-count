# Security Policy

## Reporting a vulnerability

Please report security issues privately through GitHub's
[private vulnerability reporting](https://github.com/markgustetic/pomodoro-count/security/advisories/new)
rather than opening a public issue. I'll acknowledge within a few days.

## What this app touches

Useful context when judging severity — Pomodoro Count is deliberately small:

- **One network request, for updates only.** The app fetches its Sparkle appcast
  from GitHub to see whether a newer version exists. There is no telemetry and no
  analytics, nothing about your usage is sent, and you can turn the check off in
  Settings. Nothing else in the app touches the network.
- **Updates are signature-verified.** Sparkle refuses to install an update
  unless it passes at least one of two independent checks: an EdDSA signature
  matching the public key compiled into the app, or a code signing identity
  matching the installed copy's. Releases carry both — see
  [packaging/sparkle/README.md](packaging/sparkle/README.md).
- **One third-party dependency**, [Sparkle](https://sparkle-project.org). Everything
  else is Apple frameworks.
- **Local data only.** Everything lives in a single plain-text JSON file at
  `~/Library/Application Support/PomodoroCount/data.json`, containing timestamps
  of your pomodoros and your settings. Nothing else is read or written.
- **A global hotkey**, registered with Carbon's `RegisterEventHotKey`. It listens
  for one specific key combination and does not read other keystrokes. It needs
  no Accessibility permission.
- **Launch at login**, via `SMAppService`, only when you turn it on.

## Supported versions

The latest release is supported. Fixes go into a new release rather than
patching older tags.

## Release integrity

Released builds are signed with an Apple Developer ID and notarized by Apple,
with the ticket stapled into the bundle, so Gatekeeper accepts them offline and
macOS does not warn on first launch. Every release also ships a SHA-256 checksum
if you would rather verify the download yourself:

```bash
shasum -a 256 -c PomodoroCount-*.zip.sha256
```

Builds produced locally from source are ad-hoc signed instead, which is enough to
run on the machine that built them but carries no identity — only the published
release artifacts are notarized.
