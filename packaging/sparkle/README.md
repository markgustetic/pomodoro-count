# Sparkle updates

The app checks for updates with [Sparkle](https://sparkle-project.org). It reads
an appcast published as a release asset:

```
https://github.com/markgustetic/pomodoro-count/releases/latest/download/appcast.xml
```

`releases/latest/download/…` always redirects to the newest release, so the feed
URL baked into the app never changes.

## Why an EdDSA key is required

Sparkle downloads a zip and replaces the running app with it. Anything able to
intercept that download could replace the app with something else — so Sparkle
refuses an update unless it passes at least one of two checks: the EdDSA public
key compiled into the app, or the code signing identity of the installed copy.

Releases carry both, deliberately. Without an EdDSA key the app ships with its
updater disabled rather than pretending to check, and having two strands is what
let the Developer ID certificate be introduced without stranding existing
installs — the EdDSA check carried the update across while the identity changed
underneath it. Never rotate this key in a release that also changes the
certificate: see `packaging/signing/README.md`.

## One-time setup

**1. Generate the key pair.** This stores the private key in your login Keychain
and prints the public half:

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys
```

**2. Publish the public key.** It isn't secret — it goes into the app's
Info.plist. Store it as a repository *variable* so CI builds pick it up, and in
a local file so your own builds match:

```bash
gh variable set SPARKLE_PUBLIC_KEY --body "<the public key it printed>"
mkdir -p packaging/sparkle
echo "<the public key it printed>" > packaging/sparkle/public-key.txt
```

`public-key.txt` is git-ignored so the file never disagrees with the repository
variable — the variable is the source of truth.

**3. Give CI the private key.** Export it from the Keychain and store it as a
repository *secret*:

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle-private-key.txt
gh secret set SPARKLE_PRIVATE_KEY < sparkle-private-key.txt
rm sparkle-private-key.txt        # do not commit this, ever
```

Until `SPARKLE_PRIVATE_KEY` exists the release workflow skips appcast generation
and releases publish normally, just without updates.

## Losing the private key

Every future update must be signed with the same key an installed app already
trusts. If you lose it, existing installs can never auto-update again — they'd
have to be replaced by hand. Back up the Keychain item.

## Testing an update locally

```bash
SPARKLE_PUBLIC_KEY="$(cat packaging/sparkle/public-key.txt)" ./build-app.sh
```

Then lower `CFBundleShortVersionString` in the built bundle's Info.plist below
the latest release and use **Check for updates now…** in Settings — the app
should offer the newer version.

## How a release wires together

1. `build-app.sh` bakes `SUFeedURL` and `SUPublicEDKey` into Info.plist and
   embeds `Sparkle.framework` in `Contents/Frameworks`.
2. The release workflow zips the app, signs the zip with `sign_update`, and
   writes an `appcast.xml` carrying that signature.
3. Both are attached to the GitHub Release.
4. Installed apps read the appcast, verify the signature against their embedded
   public key, and install only if it matches.
