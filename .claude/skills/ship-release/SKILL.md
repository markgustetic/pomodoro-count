---
name: ship-release
description: Use when cutting a Pomodoro Count release, bumping VERSION, writing release notes, tagging, or checking that a published release's artifacts (zip, appcast, Homebrew cask) actually landed.
---

# Shipping a release

## Overview

Everything after the tag is automated (`.github/workflows/release.yml`); the
human steps are the version judgment, the notes, and verifying the artifacts
landed. `just release` is the only way to tag — it refuses a dirty tree, a
missing CHANGELOG section, a duplicate tag, or a disabled workflow, and runs
the tests first.

## Steps

1. **Bump `VERSION`** (plain `MAJOR.MINOR.PATCH`, no v). New features → minor;
   fixes only → patch.
2. **CHANGELOG.md**: retitle `## [Unreleased]` to `## [X.Y.Z] - YYYY-MM-DD`.
   This section *becomes the release notes verbatim* — the workflow extracts
   it with awk and publishes it — so edit it as prose for users, not as a
   commit log. (A fresh empty `## [Unreleased]` above it is fine and
   conventional; the extraction only reads the version's own section.) Update
   the link definitions at the bottom — `[Unreleased]` compare becomes
   `vX.Y.Z...HEAD`, and `[X.Y.Z]` gets its own line; the notes extraction
   deliberately stops before that block.
3. Commit, push, wait for **CI green** (all four jobs).
4. `just release` — tags `vX.Y.Z` and pushes the tag, which triggers the
   Release workflow.
5. `gh run watch` the **Release** workflow (not CI).
6. **Verify the artifacts** — automation succeeding ≠ artifacts right:
   - `gh release view vX.Y.Z` → zip + `.sha256` + `appcast.xml` all attached.
     The appcast **must** ride every release: the app's feed URL is
     `releases/latest/download/appcast.xml`, so a release without it breaks
     updates for every existing user.
   - Appcast names the new version and an `edSignature` (Sparkle signing ran —
     it silently skips if the `SPARKLE_PRIVATE_KEY` secret is missing).
   - `markgustetic/homebrew-tap` got a `pomodoro-count X.Y.Z` cask commit.
7. Sanity-install one path: `brew upgrade --cask pomodoro-count` or let the
   running app's Sparkle offer the update.

## Facts that bite

| Fact | Consequence |
|---|---|
| Tag must equal `v` + VERSION | Workflow hard-fails on mismatch — never `git tag` by hand |
| Notes come from the CHANGELOG section | Sloppy CHANGELOG = sloppy public release notes |
| App is unsigned (no Developer ID secrets set) | Release notes footer explains right-click-Open; don't remove it |
| Sparkle key exists only as a GitHub secret + 1Password | Losing it orphans every installed app's updater |
| `workflow_dispatch` run releases whatever VERSION says | Useful for re-publishing a failed run; same checks apply |
