# Developer ID signing, Phase 1 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the release pipeline sign, notarize, staple and verify the app the
moment a Developer ID certificate exists — without needing one to build, test or
merge any of this today.

**Architecture:** `build-app.sh` becomes the single owner of signing and takes
the identity through a `CODESIGN_IDENTITY` environment variable, defaulting to
ad-hoc. The release workflow imports the certificate *before* the build, hands
the identity to the script, then notarizes with an App Store Connect API key and
proves the result with `spctl`. No `--deep` signing anywhere; `--deep` survives
only in verification, where recursion is what you want.

**Tech Stack:** bash, `codesign`, `xcrun notarytool`, `xcrun stapler`, `spctl`,
`security`, GitHub Actions on `macos-latest`.

## Global Constraints

- **Phase 1 must stay green with no certificate in existence.** Every signing
  step stays gated on `HAS_SIGNING` (`secrets.DEVELOPER_ID_P12 != ''`), which is
  false today. Nothing in this plan may make an unsigned build fail.
- **No user-visible change, so no CHANGELOG entry.** The repo's `just release`
  refuses to tag without one, but that gate belongs to Phase 2. Do not add one.
- **Never `codesign --deep`.** Signing is inside-out and explicit.
  `--deep` appears only in `codesign --verify`.
- **No entitlements file.** The app is not sandboxed and uses nothing the
  hardened runtime restricts.
- **Do not touch the Sparkle EdDSA key or `packaging/sparkle/`.** Sparkle permits
  changing the code signing identity *or* the EdDSA key, never both in one
  release; changing both strands every existing install permanently.
- **Do not touch the "unsigned" messaging** in `README.md`,
  `packaging/homebrew/pomodoro-count.rb.template`, or the release-notes footer in
  `.github/workflows/release.yml`. Those are Phase 2, and flipping them early
  would make the docs lie.
- **Comments record WHY and stay.** Every non-obvious line added here carries its
  reasoning in place, matching the surrounding file.
- Commit subjects are short imperative sentences; bodies explain the why.

## File Structure

| File | Responsibility after this plan |
| --- | --- |
| `build-app.sh` | Builds, bundles, and **signs** — the only place `codesign --sign` is called. Takes `CODESIGN_IDENTITY`, default `-`. |
| `.github/workflows/release.yml` | Imports the certificate, calls `build-app.sh` with the identity, notarizes, staples, verifies, publishes. Contains no `codesign --sign`. |
| `.github/workflows/ci.yml` | Verifies the ad-hoc bundle on every push, now recursively. |
| `packaging/signing/README.md` | **New.** The one-time Apple-side setup: certificate, API key, `gh secret set` commands. |
| `AGENTS.md` | Gains a signing section — who owns signing, why the walk is explicit, and the EdDSA rule. |

---

### Task 1: `build-app.sh` owns signing, and its nested walk stops silently missing code

**Files:**
- Modify: `build-app.sh:95-106` (the signing block)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `CODESIGN_IDENTITY` environment variable, a string. Default `-`
  (ad-hoc). Any other value is passed verbatim to `codesign --sign` and
  additionally enables `--options runtime --timestamp`. Task 3 sets it.

**Background the implementer needs.** The current block collects nested bundles
with `find … -maxdepth 3`. Sparkle's XPC services live four levels down, at
`Versions/B/XPCServices/{Downloader,Installer}.xpc`, so they are never re-signed
— they keep the ad-hoc signature Sparkle shipped, with `TeamIdentifier=not set`.
That is harmless while the whole bundle is ad-hoc and fatal under a Developer ID,
where unsigned nested code fails notarization with an error that does not name
the file. Verified by running the existing find: it returns `Updater.app` only.

- [ ] **Step 1: Confirm the bug before changing anything**

Run:

```bash
FW=$(find .build/artifacts -type d -name 'Sparkle.framework' -path '*macos*' | head -1)
find "$FW" \( -name '*.xpc' -o -name '*.app' \) -maxdepth 3
```

Expected: two lines, both `Updater.app` (one is the top-level symlink). **No
`.xpc` paths.** That absence is the bug.

If `.build/artifacts` does not exist yet, run `swift package resolve` first.

- [ ] **Step 2: Replace the signing block**

In `build-app.sh`, replace lines 95-106 — everything from the
`# Ad-hoc signature so macOS treats this…` comment through
`codesign --force --sign - "$APP"` — with:

```bash
# Signing. CODESIGN_IDENTITY defaults to ad-hoc, which is enough for macOS to
# treat this as a stable, launchable app on the machine that built it. A release
# passes a real Developer ID; that path also needs the hardened runtime (the
# notary service rejects submissions without it) and a secure timestamp (which
# keeps the signature valid after the certificate expires).
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
if [ "$CODESIGN_IDENTITY" = "-" ]; then
    echo "Signing (ad-hoc)…"
    SIGN=(codesign --force --sign - --timestamp=none)
else
    echo "Signing as $CODESIGN_IDENTITY …"
    SIGN=(codesign --force --sign "$CODESIGN_IDENTITY" --options runtime --timestamp)
fi

# Nested code must be signed before the thing that contains it, innermost first —
# signing the outer bundle first would seal a hash the inner signatures then
# invalidate.
#
# The list is explicit and a missing entry is fatal, because the failure it
# replaces was silent: a `find -maxdepth 3` here never reached
# Versions/*/XPCServices, so both XPC services kept the ad-hoc signature Sparkle
# ships them with. Invisible while everything was ad-hoc, fatal under a Developer
# ID. A Sparkle upgrade that moves these should break the build here, loudly,
# rather than at Apple's notary service, obscurely.
FW="$APP/Contents/Frameworks/Sparkle.framework"
FW_VER="$(readlink "$FW/Versions/Current")"   # "B" today — read, not hardcoded
for nested in \
    "XPCServices/Downloader.xpc" \
    "XPCServices/Installer.xpc" \
    "Updater.app" \
    "Autoupdate"
do
    target="$FW/Versions/$FW_VER/$nested"
    [ -e "$target" ] || {
        echo "Sparkle.framework has no $nested — did its layout change?" >&2
        exit 1
    }
    "${SIGN[@]}" "$target"
done
"${SIGN[@]}" "$FW"
"${SIGN[@]}" "$APP"
```

Note what else this removes: the old block ended several `codesign` calls with
`2>/dev/null || true`, which swallowed real failures. They are gone. A signing
error is now a build error.

- [ ] **Step 3: Build, and prove all four nested items got signed**

Run:

```bash
just build
```

Expected: the `Signing (ad-hoc)…` line, then `Done → build/Pomodoro Count.app`,
exit 0.

Then verify the walk reached everything:

```bash
APP="build/Pomodoro Count.app"
FW="$APP/Contents/Frameworks/Sparkle.framework"
VER=$(readlink "$FW/Versions/Current")
for n in XPCServices/Downloader.xpc XPCServices/Installer.xpc Updater.app Autoupdate; do
  printf '%-32s ' "$n"; codesign --verify --strict "$FW/Versions/$VER/$n" && echo OK
done
codesign --verify --strict --deep --verbose=2 "$APP"
```

Expected: `OK` on all four lines, and the final verify prints
`valid on disk` / `satisfies its Designated Requirement`.

- [ ] **Step 4: Prove the guard actually fires**

The point of the explicit list is that a layout change fails loudly rather than
signing three of four binaries and continuing. Prove the guard fires by hiding
one and rebuilding.

`build-app.sh` re-copies the framework from `.build/artifacts` on every run, so
hide it at the source — otherwise the rebuild silently restores what you moved:

```bash
FW_SRC=$(find .build/artifacts -type d -name 'Sparkle.framework' -path '*macos*' | head -1)
mv "$FW_SRC/Versions/B/Updater.app" "$FW_SRC/Versions/B/Updater.app.hidden"
./build-app.sh; echo "exit: $?"
```

Expected: `Sparkle.framework has no Updater.app — did its layout change?` on
stderr, and `exit: 1`.

Restore it immediately — a hidden binary here breaks every later build:

```bash
mv "$FW_SRC/Versions/B/Updater.app.hidden" "$FW_SRC/Versions/B/Updater.app"
./build-app.sh && echo "restored and building again"
```

Expected: a normal build, exit 0.

- [ ] **Step 5: Confirm the app still launches**

A signing change that produces an unlaunchable bundle passes every check above.

```bash
just install
```

Expected: the app appears in the menu bar. Click the icon; the panel opens.

- [ ] **Step 6: Commit**

```bash
git add build-app.sh
git commit -m "$(cat <<'EOF'
Let build-app.sh sign with a real identity, and reach every nested binary

Signing was split between this script (ad-hoc, inside-out) and the release
workflow (codesign --deep, over the top). --deep is Apple's emergency
repair tool, not a build step: it re-signs whatever it finds with one set
of options and reports what it got wrong as a notarization rejection days
later. The inside-out walk was already correct, so it is the one that stays
— it just needs the identity handed to it.

The walk was also short. -maxdepth 3 never reached
Versions/*/XPCServices, so both of Sparkle's XPC services kept the ad-hoc
signature they ship with. That is invisible today and fatal under a
Developer ID, where unsigned nested code fails notarization without naming
the file. The list is now explicit, and a Sparkle layout change breaks the
build here rather than at Apple.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
git push
```

---

### Task 2: CI verifies the whole bundle, not just its shell

**Files:**
- Modify: `.github/workflows/ci.yml:53`

**Interfaces:**
- Consumes: the nested signing from Task 1.
- Produces: nothing later tasks read.

**Background.** `ci.yml:53` already runs `codesign --verify --strict "$APP"`.
Without `--deep` that stops at the outer bundle and says nothing about the
framework or the four nested binaries — exactly the surface Task 1 changed. This
runs on every push, so it guards the signing order continuously rather than only
on a tag.

- [ ] **Step 1: Make the check recursive**

In `.github/workflows/ci.yml`, replace line 53:

```yaml
          codesign --verify --strict "$APP"
```

with:

```yaml
          # --deep, because the interesting failures are all nested: an outer
          # signature that seals a stale hash from the framework or one of
          # Sparkle's four inner binaries is silent until something recurses.
          codesign --verify --strict --deep "$APP"
```

- [ ] **Step 2: Run the same check locally**

```bash
codesign --verify --strict --deep --verbose=2 "build/Pomodoro Count.app"
```

Expected: `valid on disk`, `satisfies its Designated Requirement`, exit 0.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "$(cat <<'EOF'
Verify the bundle's nested code, not just its outer signature

codesign --verify without --deep checks the app wrapper and stops. Every
failure mode the signing walk can have lives below that line — the Sparkle
framework and its four inner binaries — so the check that runs on every
push was the one check that could not see them.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
git push
```

- [ ] **Step 4: Confirm CI is green**

```bash
gh run watch
```

Expected: all four jobs pass, **App bundle** included.

---

### Task 3: The release workflow signs, notarizes with an API key, and proves it

**Files:**
- Modify: `.github/workflows/release.yml:15-21` (job `env`), `:51-96` (the build
  and the old sign-and-notarize step)

**Interfaces:**
- Consumes: `CODESIGN_IDENTITY` from Task 1.
- Produces: a step with `id: signing` whose output `identity` is the Developer ID
  string, empty when signing is off.

**Background.** Today the workflow builds unsigned, then re-signs with `--deep`
and notarizes with an Apple ID and app-specific password. Three changes: the
certificate import moves *ahead* of the build so the script can sign once;
notarization switches to an App Store Connect API key, which is not revoked when
an Apple ID password changes; and a verification step asserts what Gatekeeper
will actually conclude.

There is deliberately no `DEVELOPER_ID_IDENTITY` secret. The identity is read
back out of the keychain and asserted to be a Developer ID Application
certificate — the machine this is set up from holds an `Apple Development`
certificate, which is the one that is easy to export by mistake, signs fine, and
notarizes never.

- [ ] **Step 1: Drop the stale secret from the job env**

In `.github/workflows/release.yml`, the `HAS_SIGNING` line (`:18`) is unchanged —
`DEVELOPER_ID_P12` remains the presence check. No edit in this step; this is a
read-and-confirm so the next steps land in a known place.

Confirm `:15-21` currently reads:

```yaml
    env:
      HAS_SIGNING: ${{ secrets.DEVELOPER_ID_P12 != '' }}
      HAS_TAP_TOKEN: ${{ secrets.HOMEBREW_TAP_TOKEN != '' }}
      HAS_SPARKLE_KEY: ${{ secrets.SPARKLE_PRIVATE_KEY != '' }}
      SPARKLE_PUBLIC_KEY: ${{ vars.SPARKLE_PUBLIC_KEY }}
```

- [ ] **Step 2: Insert the certificate import before the build**

Replace the `Build the .app` step (`:51-52`, including its two comment lines at
`:48-50`) with the following three steps, in this order:

```yaml
      - name: Import the signing certificate
        id: signing
        if: env.HAS_SIGNING == 'true'
        env:
          P12: ${{ secrets.DEVELOPER_ID_P12 }}
          P12_PASSWORD: ${{ secrets.DEVELOPER_ID_P12_PASSWORD }}
        run: |
          set -euo pipefail
          keychain="$RUNNER_TEMP/build.keychain"
          password="$(uuidgen)"
          security create-keychain -p "$password" "$keychain"
          security set-keychain-settings -lut 900 "$keychain"
          security unlock-keychain -p "$password" "$keychain"
          security list-keychains -d user -s "$keychain" $(security list-keychains -d user | tr -d '"')

          echo "$P12" | base64 --decode > "$RUNNER_TEMP/cert.p12"
          security import "$RUNNER_TEMP/cert.p12" -k "$keychain" -P "$P12_PASSWORD" \
            -T /usr/bin/codesign
          security set-key-partition-list -S apple-tool:,apple:,codesign: \
            -s -k "$password" "$keychain" >/dev/null
          rm -f "$RUNNER_TEMP/cert.p12"

          # Read the identity out of the keychain rather than carrying it as a
          # secret. A stored string can disagree with the certificate, and what
          # that produces is "no identity found" at codesign time. Asserting the
          # prefix catches the certificate that is easy to export by mistake: an
          # "Apple Development" cert signs fine and notarizes never.
          found="$(security find-identity -v -p codesigning "$keychain" |
                   sed -n 's/.*"\(.*\)".*/\1/p')"
          identity="$(printf '%s\n' "$found" |
                      grep '^Developer ID Application: ' | head -1 || true)"
          if [ -z "$identity" ]; then
            echo "The imported .p12 holds no 'Developer ID Application' certificate."
            echo "It holds: ${found:-<nothing>}"
            exit 1
          fi
          echo "identity=$identity" >> "$GITHUB_OUTPUT"
          echo "Signing as $identity"

      # SPARKLE_PUBLIC_KEY comes from a repository variable (it isn't secret).
      # Without it the app builds with its updater disabled rather than shipping
      # one that can't verify anything.
      #
      # CODESIGN_IDENTITY is empty when signing is off, and build-app.sh reads
      # that as ad-hoc — the same bundle every CI push already produces.
      - name: Build the .app
        env:
          CODESIGN_IDENTITY: ${{ steps.signing.outputs.identity }}
        run: ./build-app.sh
```

- [ ] **Step 3: Replace the old sign-and-notarize step**

Delete the entire `Sign and notarize` step — the comment block at `:54-59` plus
the step at `:60-96` — and put these two in its place:

```yaml
      # Inert until a Developer ID exists. Add these repository secrets to turn
      # it on, with no other change needed — see packaging/signing/README.md:
      #   DEVELOPER_ID_P12          base64 of the exported .p12
      #   DEVELOPER_ID_P12_PASSWORD
      #   NOTARY_KEY_ID, NOTARY_ISSUER_ID, NOTARY_KEY_P8
      - name: Notarize and staple
        if: env.HAS_SIGNING == 'true'
        env:
          NOTARY_KEY_ID: ${{ secrets.NOTARY_KEY_ID }}
          NOTARY_ISSUER_ID: ${{ secrets.NOTARY_ISSUER_ID }}
          NOTARY_KEY_P8: ${{ secrets.NOTARY_KEY_P8 }}
          APP: build/Pomodoro Count.app
        run: |
          set -euo pipefail
          keyfile="$RUNNER_TEMP/notary.p8"
          printf '%s' "$NOTARY_KEY_P8" > "$keyfile"
          trap 'rm -f "$keyfile"' EXIT
          chmod 600 "$keyfile"

          # An App Store Connect API key, not an Apple ID and app-specific
          # password: the password is revoked whenever that account's password
          # changes, which breaks releases months later for an unrelated reason.
          ditto -c -k --keepParent "$APP" "$RUNNER_TEMP/notarize.zip"
          xcrun notarytool submit "$RUNNER_TEMP/notarize.zip" \
            --key "$keyfile" \
            --key-id "$NOTARY_KEY_ID" \
            --issuer "$NOTARY_ISSUER_ID" \
            --wait
          # Staples the ticket into the bundle so first launch needs no network.
          xcrun stapler staple "$APP"

      - name: Verify Gatekeeper accepts it
        if: env.HAS_SIGNING == 'true'
        env:
          APP: build/Pomodoro Count.app
        run: |
          set -euo pipefail
          codesign --verify --strict --deep --verbose=2 "$APP"
          xcrun stapler validate "$APP"

          # The question a release actually has to answer: what does Gatekeeper
          # do with this on a machine that has never seen it. spctl exits zero
          # for other accept sources too — "the user already trusts it" — so the
          # source is asserted, not just the exit code. This runs after stapling,
          # so it resolves from the embedded ticket rather than the network.
          assessment="$(spctl --assess --type execute --verbose=4 "$APP" 2>&1)"
          echo "$assessment"
          case "$assessment" in
            *"source=Notarized Developer ID"*) ;;
            *) echo "Gatekeeper did not accept this as notarized"; exit 1 ;;
          esac

          # Every nested binary must carry the app's Team ID. This is the check
          # that would have caught the -maxdepth walk which skipped Sparkle's XPC
          # services: they stayed ad-hoc, with no team at all, and notarization
          # failed without naming them.
          team="$(codesign -dvv "$APP" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
          [ -n "$team" ] || { echo "the app has no TeamIdentifier"; exit 1; }
          fw="$APP/Contents/Frameworks/Sparkle.framework"
          ver="$(readlink "$fw/Versions/Current")"
          for nested in XPCServices/Downloader.xpc XPCServices/Installer.xpc \
                        Updater.app Autoupdate; do
            got="$(codesign -dvv "$fw/Versions/$ver/$nested" 2>&1 |
                   sed -n 's/^TeamIdentifier=//p')"
            [ "$got" = "$team" ] \
              || { echo "$nested has TeamIdentifier '${got:-not set}', want '$team'"; exit 1; }
          done
          echo "Signed, notarized, stapled — team $team"
```

- [ ] **Step 4: Check the workflow parses and the step order is right**

```bash
python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/release.yml')); print('YAML OK')"
grep -n '^      - name:' .github/workflows/release.yml
```

Expected: `YAML OK`, and the step names in this order — Resolve version, Run
tests before releasing, Import the signing certificate, Build the .app, Notarize
and staple, Verify Gatekeeper accepts it, Package, Build the Sparkle appcast,
Extract release notes from the changelog, Publish the release, Update the
Homebrew cask.

Packaging must come *after* stapling, or the published zip contains an
un-stapled app. Confirm that ordering explicitly.

- [ ] **Step 5: Confirm no `codesign --sign` survives in the workflow**

```bash
grep -n 'codesign' .github/workflows/release.yml
```

Expected: only `codesign --verify --strict --deep --verbose=2` and the two
`codesign -dvv` reads. **No `--sign`, no `--deep` outside `--verify`.** If a
`--sign` appears, the old step was not fully removed.

- [ ] **Step 6: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "$(cat <<'EOF'
Sign once, notarize with an API key, and prove Gatekeeper agrees

The certificate import moves ahead of the build so build-app.sh can do all
the signing itself, which retires the codesign --deep pass that used to
overwrite it.

Notarization moves from an Apple ID and app-specific password to an App
Store Connect API key. An app-specific password is revoked whenever that
account's password changes, so the old arrangement would have broken a
release months later for a reason with nothing to do with releasing.

The identity is no longer a secret. It is read back out of the keychain and
asserted to be a Developer ID Application certificate, because an Apple
Development certificate is the easy mistake and it signs fine and notarizes
never.

Verification asserts spctl's source rather than its exit code — spctl also
exits zero for "the user already trusts it", which proves nothing about a
stranger's machine — and checks that every nested Sparkle binary carries
the app's team.

All of it stays gated on DEVELOPER_ID_P12, which does not exist yet.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
git push
```

- [ ] **Step 7: Rehearse the unsigned path end to end**

The workflow must still work with no secrets. Trigger it by hand:

```bash
gh workflow run release.yml && sleep 5 && gh run watch
```

Expected: green. **Import the signing certificate**, **Notarize and staple** and
**Verify Gatekeeper accepts it** all skip. The release publishes as today.

If a `v$(cat VERSION)` release already exists, `gh release create` fails at the
last step — that is expected and not a signing failure. Everything up to and
including Package must be green.

---

### Task 4: Write down the one-time Apple setup

**Files:**
- Create: `packaging/signing/README.md`
- Modify: `AGENTS.md` (new section after "Theming")

**Interfaces:**
- Consumes: the secret names from Task 3.
- Produces: nothing code reads.

**Background.** `packaging/` already holds `sparkle/README.md` and
`homebrew/README.md` for exactly this — one-time setup that is painful to
reconstruct from memory belongs next to the thing it configures.

- [ ] **Step 1: Write `packaging/signing/README.md`**

```markdown
# Developer ID signing

One-time setup. Once the five secrets below exist, the release workflow signs,
notarizes and staples every tagged build with no further intervention.

Prerequisite: an Apple Developer Program membership ($99/yr,
<https://developer.apple.com/programs/>). Enrollment can take a day or two.

## 1. The certificate

1. Keychain Access → Certificate Assistant → **Request a Certificate From a
   Certificate Authority**. Save the `.certSigningRequest` to disk.
2. <https://developer.apple.com/account/resources/certificates> → **+** →
   **Developer ID Application**. Upload the request, download the `.cer`.
3. Double-click the `.cer` to add it to the login keychain.
4. In Keychain Access, find **Developer ID Application: … (TEAMID)**, expand it
   so the private key shows, right-click → **Export 2 items** → `.p12`. Set an
   export password.

`Developer ID Application` is the only certificate that works here. An
**Apple Development** certificate signs without complaint and is rejected by the
notary service; the workflow checks for the prefix and fails at import rather
than letting you find out from Apple.

## 2. The notary API key

<https://appstoreconnect.apple.com/access/integrations/api> → **Keys** → **+**,
role **Developer**. Download the `.p8` — Apple lets you download it once. Note
the **Key ID** and the **Issuer ID** shown above the table.

An API key rather than an Apple ID and app-specific password: the password is
revoked whenever the Apple ID's password changes, which breaks releases later for
a reason unconnected to releasing.

## 3. The secrets

```sh
base64 -i Certificates.p12 | gh secret set DEVELOPER_ID_P12
gh secret set DEVELOPER_ID_P12_PASSWORD      # the .p12 export password
gh secret set NOTARY_KEY_ID                  # e.g. 2X9R4HXF34
gh secret set NOTARY_ISSUER_ID               # the issuer UUID
gh secret set NOTARY_KEY_P8 < AuthKey_XXXX.p8
```

`DEVELOPER_ID_P12` is also the presence check that switches the signing steps on.
There is no identity secret — the workflow reads it out of the keychain.

Delete the `.p12` and `.p8` from disk afterwards.

## 4. Then

See the Phase 2 section of
`docs/superpowers/specs/2026-07-30-developer-id-signing-design.md`: make signing
mandatory for tag builds, and remove the "unsigned" workaround text from the
README, the cask caveats and the release notes.

## Signing locally

`just build` and `just install` sign ad-hoc. A locally built app is never
quarantined, so there is nothing to clear, and notarizing would add minutes of
waiting on Apple to every iteration.

To rehearse the signed path without a release:

```sh
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build-app.sh
```

## The rule that will bite you

Sparkle validates an update against **either** the EdDSA key **or** the code
signing identity, and permits exactly one of them to change per release. Changing
both at once leaves neither check able to pass, and every existing install
refuses the update permanently — there is no route back except a manual
reinstall. Never rotate `packaging/sparkle/` keys in a release that also changes
the certificate.
```

- [ ] **Step 2: Add the `AGENTS.md` section**

Insert after the "Theming" section and before "Conventions":

```markdown
## Signing

`build-app.sh` is the only place that calls `codesign --sign`. It takes
`CODESIGN_IDENTITY` (default `-`, ad-hoc); a real identity also gets
`--options runtime --timestamp`, both of which notarization requires. The
release workflow imports the certificate, reads the identity back out of the
keychain, and hands it to the script — it does no signing of its own, and
`--deep` appears only in `codesign --verify`, never in signing.

The nested walk is an **explicit list** of Sparkle's four inner binaries, and a
missing one fails the build. It replaced a `find -maxdepth 3` that never reached
`Versions/*/XPCServices`, so both XPC services silently kept the ad-hoc signature
Sparkle ships — invisible while everything was ad-hoc, fatal under a Developer
ID. A Sparkle upgrade that moves them should break here, not at Apple.

Sparkle accepts an update whose **EdDSA key** matches *or* whose **code signing
identity** matches — one may change per release, never both. Changing both
strands every existing install permanently. One-time Apple-side setup is in
`packaging/signing/README.md`.
```

- [ ] **Step 3: Check the links resolve**

```bash
test -f packaging/signing/README.md && echo "README OK"
test -f docs/superpowers/specs/2026-07-30-developer-id-signing-design.md && echo "spec OK"
grep -c "packaging/signing/README.md" AGENTS.md .github/workflows/release.yml
```

Expected: both `OK` lines, and each file referencing the README at least once.

- [ ] **Step 4: Commit**

```bash
git add packaging/signing/README.md AGENTS.md
git commit -m "$(cat <<'EOF'
Write down the Apple-side setup before it is needed

Certificates and notary keys are created once, from a browser, and are
miserable to reconstruct from memory a year later — the same reason
packaging/sparkle and packaging/homebrew have READMEs.

Records the trap most likely to cost a release too: Sparkle validates an
update on either the EdDSA key or the code signing identity and allows one
of them to change at a time, so rotating both together strands every
existing install with no route back.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
git push
```

---

## Done when

- `just build` signs ad-hoc and `codesign --verify --strict --deep` passes on the
  result, including all four nested Sparkle binaries.
- `just install` produces a running menu bar app.
- All four CI jobs are green.
- A `workflow_dispatch` run of `release.yml` is green with the signing steps
  skipped.
- No `codesign --sign` exists outside `build-app.sh`.
- `README.md`, the cask template and the release-notes footer are **unchanged** —
  they still describe an unsigned app, which is still true.

## Self-review notes

Checked against the spec: the `CODESIGN_IDENTITY` parameter (Task 1), the
`-maxdepth` fix (Task 1), the workflow restructure and API-key notarization
(Task 3), the five secrets and the absent identity secret (Tasks 3 and 4), the
`spctl` source assertion (Task 3), the `--deep` verify in CI (Task 2), local
builds staying ad-hoc (Tasks 1 and 4), and the EdDSA rule recorded in two places
(Task 4). Phase 2 items — the mandatory-signing gate flip and the messaging
removal — are deliberately absent; they are listed under "Done when" as things
that must *not* change.
