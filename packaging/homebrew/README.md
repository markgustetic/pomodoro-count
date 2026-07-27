# Homebrew distribution

Users install with:

```bash
brew install --cask markgustetic/tap/pomodoro-count
```

That resolves to the GitHub repo `markgustetic/homebrew-tap`, which Homebrew
requires to be **public** and named with the `homebrew-` prefix.

## One-time setup

1. Create the tap repo:

   ```bash
   gh repo create markgustetic/homebrew-tap --public \
     --description "Homebrew tap for markgustetic's tools"
   ```

2. Create a fine-grained personal access token scoped to **that repo only**,
   with **Contents: read and write**, and add it to *this* repo as the secret
   `HOMEBREW_TAP_TOKEN`:

   ```bash
   gh secret set HOMEBREW_TAP_TOKEN --repo markgustetic/pomodoro-count
   ```

   `GITHUB_TOKEN` can't be used — it only has access to the repo running the
   workflow, not the tap.

Until `HOMEBREW_TAP_TOKEN` exists the release workflow skips the cask step
entirely, so releases still publish normally.

## How updates happen

On every release, the workflow renders `pomodoro-count.rb.template` with the new
version and the zip's SHA-256, then commits it to the tap. Edit the template
here — never the generated file in the tap, which is overwritten each release.

## Checking the cask by hand

```bash
brew tap markgustetic/tap
brew audit --cask --online markgustetic/tap/pomodoro-count
brew install --cask --no-quarantine markgustetic/tap/pomodoro-count
```

`--no-quarantine` matters: the app is unsigned, so without it macOS blocks the
first launch. The cask's caveats tell users the same thing.
