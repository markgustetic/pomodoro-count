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
- **Updates are signature-verified.** Every update must carry a valid EdDSA
  signature matching the public key compiled into the app, or Sparkle refuses to
  install it. Since the app isn't notarized, that signature is the main integrity
  guarantee — see [packaging/sparkle/README.md](packaging/sparkle/README.md).
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

## Unsigned releases

Released builds are **not** signed with an Apple Developer ID and are **not**
notarized, so macOS asks you to confirm the first launch. That also means the
usual signature check can't tell you the download is untampered — so verify the
SHA-256 checksum published with each release, or build from source.
