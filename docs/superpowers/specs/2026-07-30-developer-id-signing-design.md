# Developer ID signing and notarization

**Date:** 2026-07-30
**Status:** shipped in v1.4.0 (`ef11af2`). Phase 1 landed ahead of enrollment;
Phase 2 — the certificate, the notary key, the five secrets, the mandatory gate
on tag builds, and the removal of the workaround messaging — landed in `318f22c`
and `6360358`. The Rollout section below is kept as written, as the record of
how the work was split around an enrollment that had not happened yet.

A released Pomodoro Count launches with no warning on a machine that has never
seen it — no "right-click → Open", no `xattr -dr com.apple.quarantine`, no
caveat in the cask telling people to work around macOS.

## Why

Every build the project has ever shipped is ad-hoc signed. `codesign --sign -`
produces a signature with no identity behind it, which is enough for macOS to
treat the bundle as stable and launchable but not enough to clear Gatekeeper. A
downloaded copy carries a quarantine flag, and a quarantined app with no
Developer ID is refused on first launch.

The project has been honest about it — the README, the cask caveats, and the
release notes each explain the workaround — but the workaround is the problem.
It asks a first-time user to override a security warning before they have any
reason to trust the app, and `--no-quarantine` teaches a habit that is bad
everywhere else.

Clearing the warning takes three things, and all three are required. A signature
from a **Developer ID Application** certificate. The **hardened runtime**, which
notarization will not accept a submission without. And a **notarization ticket**
from Apple, stapled into the bundle so the check succeeds offline.

## Scope

In: signing and notarizing the release bundle, the verification that proves it
worked, and the messaging that currently promises the opposite.

Out:

- **The App Store.** A different certificate, a sandbox, and a review queue. The
  app is distributed from GitHub Releases and Homebrew, and stays that way.
- **Sandboxing.** Nothing here requires it. Sparkle's XPC services exist for
  sandboxed hosts; this app is not one, and the services are signed rather than
  removed because removing them is a behaviour change this work does not need.
- **An entitlements file.** A non-sandboxed app under the hardened runtime needs
  entitlements only for the things it restricts — JIT, unsigned memory,
  DYLD overrides, Apple Events, library validation. The app does none of them:
  `Sources/` contains no `AXIsProcessTrusted`, `NSAppleScript`, or Apple Events
  usage, and the only library it loads is a Sparkle framework signed with the
  same Team ID, which library validation accepts on its own.
- **Notarizing local builds.** See Local builds.
- **Rotating the Sparkle EdDSA key.** Explicitly forbidden here — see Sparkle
  continuity.

## Where signing happens today

Twice, in two places, with the second overwriting the first.

`build-app.sh` signs the bundle inside-out with an ad-hoc identity
(build-app.sh:98-106), which is the correct order: nested code must be signed
before the thing containing it, or the outer signature seals a hash the inner
signatures then invalidate. Then the release workflow throws that away and
re-signs with `codesign --force --deep` (release.yml:86).

`--deep` is the part to remove. Apple's own guidance is that it exists for
emergency repairs, not for building; it re-signs whatever it finds with one set
of options, and when it gets something wrong the failure arrives later as an
opaque notarization rejection rather than as a signing error. The inside-out
walk that `build-app.sh` already does is the supported shape, and it is the one
that stays.

## Architecture

`build-app.sh` owns signing, once, and takes the identity as input.

```
CODESIGN_IDENTITY   default "-"   the identity to sign with
```

With the default, behaviour is exactly today's: ad-hoc, no timestamp, no
hardened runtime. With a real identity, each `codesign` call also gets
`--options runtime --timestamp`. The hardened runtime is not optional — the
notary service rejects submissions without it — and the secure timestamp is what
keeps the signature valid after the certificate expires.

The signing order is unchanged, and now covers everything:

1. `Sparkle.framework/Versions/B/XPCServices/Downloader.xpc`
2. `Sparkle.framework/Versions/B/XPCServices/Installer.xpc`
3. `Sparkle.framework/Versions/B/Updater.app`
4. `Sparkle.framework/Versions/B/Autoupdate`
5. `Sparkle.framework`
6. `Pomodoro Count.app`

The alternative — keeping ad-hoc signing in `build-app.sh` and doing Developer
ID signing in the workflow — was rejected because it leaves two signing paths,
one of which only ever runs on a tag push. The interesting failures in signing
are all in the nested walk, and a nested walk that runs on every `just build` is
one a person notices breaking.

### The bug this surfaces

build-app.sh:99 collects nested bundles with `-maxdepth 3`. The XPC services sit
four levels down (`Versions/B/XPCServices/Downloader.xpc`), so the find returns
`Updater.app` and nothing else. Verified by running it against the resolved
framework: two `.xpc` bundles, zero matches.

Today this is invisible. Everything is ad-hoc, the services keep the ad-hoc
signature Sparkle shipped them with, and nothing checks whose ad-hoc signature
it is. Under Developer ID it is fatal: two nested binaries would carry a foreign
signature and no hardened runtime, and the notary service rejects the whole
submission for it.

The `-maxdepth` bound goes. It was never doing anything a `-name` match wasn't
already doing.

## Notarization

Authentication is an **App Store Connect API key**, not an Apple ID with an
app-specific password. An app-specific password is bound to the Apple ID that
issued it and is revoked whenever that account's password changes — a release
pipeline that breaks silently, months later, for a reason unconnected to the
release. An API key is revocable on its own, scoped to a role, and survives
account maintenance.

Repository secrets:

| Secret | Contents |
| --- | --- |
| `DEVELOPER_ID_P12` | base64 of the exported `.p12` |
| `DEVELOPER_ID_P12_PASSWORD` | its export password |
| `NOTARY_KEY_ID` | API key ID |
| `NOTARY_ISSUER_ID` | issuer UUID |
| `NOTARY_KEY_P8` | the `.p8` private key, verbatim |

`DEVELOPER_ID_P12` doubles as the presence check that gates the signing steps,
as `SPARKLE_PRIVATE_KEY` and `HOMEBREW_TAP_TOKEN` already do for theirs.

There is deliberately no `DEVELOPER_ID_IDENTITY` secret. The identity string is
not a secret, and storing it invites the failure where the string and the
certificate disagree and `codesign` fails with an unhelpful "no identity found".
It is read back out of the temporary keychain after import:

```sh
identity="$(security find-identity -v -p codesigning "$keychain" |
    sed -n 's/.*"\(.*\)".*/\1/p' | head -1)"
```

and then **asserted** to begin with `Developer ID Application:`. That assertion
is the point. The machine this is being set up from currently holds exactly one
identity, `Apple Development: …`, which is the certificate someone reaches for
by mistake; it signs fine and notarizes never. Failing at import with a clear
message beats failing at the notary service with an obscure one.

### Workflow shape

Steps become, in order:

1. Resolve version — unchanged.
2. Run tests — unchanged.
3. **Import the signing certificate** (when `HAS_SIGNING`) — the existing
   temporary-keychain dance from release.yml:72-84, plus the identity read-back
   and its assertion, exported for later steps.
4. **Build the .app** — gains `CODESIGN_IDENTITY` from step 3. Unsigned builds
   pass nothing and get today's ad-hoc bundle.
5. **Notarize and staple** (when `HAS_SIGNING`) — `ditto` to a zip,
   `notarytool submit --key … --key-id … --issuer … --wait`, `stapler staple`.
6. **Verify** (when `HAS_SIGNING`) — see below.
7. Package, appcast, notes, publish, cask — unchanged.

The certificate import moves ahead of the build; everything else keeps its
current position.

## Verification

This repository does not take behaviour on trust, and a signature is behaviour.
Three checks run against the stapled bundle, and any failure fails the release:

```sh
codesign --verify --strict --deep --verbose=2 "$APP"
spctl --assess --type execute --verbose "$APP"
stapler validate "$APP"
```

`spctl` is the one that answers the actual question. It is the same assessment
Gatekeeper performs, and on a correctly signed, notarized, stapled bundle it
reports `source=Notarized Developer ID`. That string is asserted, not eyeballed:
`spctl` exits zero for other accept sources too, and "accepted because the user
already trusts it" is not what a release needs to prove. The check runs after
stapling so it resolves from the embedded ticket rather than the network.

`--deep` is correct for `codesign --verify` — verification is exactly the
recursive read that signing should not be.

## Sparkle continuity

Users on v1.3.0 are running an ad-hoc signed copy. The release that introduces
Developer ID signing changes the code signing identity out from under them, and
Sparkle validates updates before installing them. This does not strand them, and
the reason is worth recording because the safe path is narrow.

Sparkle 2.9.4's `SUUpdateValidator.m` states the rule above
`validateUpdateForHost:`:

> If the update is a bundle, then it must meet any one of: old and new Ed(DSA)
> public keys are the same and valid (it allows change of Code Signing
> identity), or old and new Code Signing identity are the same and valid

and the method ends `if (passedDSACheck || passedCodeSigning) return YES;`. The
installed app carries `SUPublicEDKey`, the release workflow signs every archive
with the matching private key, so the EdDSA check passes and the identity change
is permitted. `passesBasicUpdatePolicy` is also satisfied: it rejects *removing*
code signing, and this adds it.

The constraint that falls out: **the Sparkle EdDSA key must not change in the
same release that introduces Developer ID signing.** Sparkle allows rotating one
or the other, never both — with both changed, neither check can pass and every
existing install refuses the update permanently, with no route back short of a
manual reinstall. This gets a comment in `build-app.sh` beside the key handling,
where someone rotating the key would be standing.

## Local builds

`just build` and `just install` stay ad-hoc. A bundle built and copied locally
never receives a quarantine flag, so there is no warning to clear, and
notarization would add minutes of waiting on Apple to every iteration of a
workflow whose whole point is that it is fast.

The identity is opt-in: `CODESIGN_IDENTITY="Developer ID Application: …"
./build-app.sh` signs locally for anyone who wants to check the signing path
before trusting it to a tag push. Notarization stays a workflow step regardless.

## Rollout

The Developer ID certificate does not exist yet and cannot until an Apple
Developer Program enrollment completes, so the work splits at that line.

**Phase 1 — no membership required.** Everything above except the secrets: the
`CODESIGN_IDENTITY` parameter, the `-maxdepth` fix, the workflow restructure,
the API-key notarization step, the verification step. All of it is reachable
through the ad-hoc path, so it is testable and shippable today. Signing steps
stay gated on `HAS_SIGNING` and stay dormant.

**Phase 2 — after enrollment.** Create the Developer ID Application certificate
and the App Store Connect API key, add the five secrets, and then:

- **Flip the gate.** `HAS_SIGNING` changes from *skip when absent* to *fail when
  absent on a tag build*. Once the documentation says the app is signed, a
  release that quietly is not — an expired certificate, a revoked key, a
  deleted secret — is worse than a release that does not happen. The
  `workflow_dispatch` path keeps the permissive behaviour so an unsigned test
  build stays possible.
- **Remove the workaround messaging**, all three copies: the release-notes
  footer (release.yml:186-188), the cask caveats
  (`packaging/homebrew/pomodoro-count.rb.template`), and README.md:34-75. The
  cask's `--no-quarantine` install line goes with them.
- **Confirm on a clean machine** — download the published zip, drag it across,
  launch it. This is the only check that proves the thing the work set out to
  do; `spctl` in CI is a proxy for it.

## Testing

Signing is shell, not Swift, so it is covered by CI running it rather than by
`Tests/PomodoroCountTests`.

- The existing **App bundle** job already runs `build-app.sh` on every push and
  so exercises the default ad-hoc path, including the widened nested walk. A
  `-maxdepth` regression breaks it.
- That job's `codesign --verify --strict` (ci.yml:53) gains `--deep`. Without
  it, verification stops at the outer bundle and says nothing about the nested
  code — which is the whole of what this change touches. It passes for an
  ad-hoc signature too, so it guards the nested signing order on every push
  rather than only on a release; the failure mode where an outer signature
  seals a stale inner hash is otherwise silent until Apple rejects it.
- The verification step in the release workflow covers the signed path, and
  runs on `workflow_dispatch` as well as on tags, so the pipeline can be
  rehearsed without cutting a release.

## Documentation

CHANGELOG gets a Changed entry under Unreleased when phase 2 lands, not when
phase 1 does: phase 1 changes nothing a user can observe.

`AGENTS.md` gains a short paragraph under a signing heading — that
`build-app.sh` owns all signing and takes `CODESIGN_IDENTITY`, that the nested
walk is inside-out and why, and the EdDSA-or-identity rule that forbids rotating
the Sparkle key alongside the certificate. The last is the one a future change
would otherwise trip over.

`packaging/` gains `signing/README.md`, alongside the `sparkle/` and `homebrew/`
READMEs it already has, documenting the one-time setup: creating the certificate,
exporting the `.p12`, creating the API key, and the exact `gh secret set`
commands. The Sparkle README is the model — one-time setup that is painful to
reconstruct from memory belongs written down next to the thing it configures.
