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

## 4. Confirm it worked

A tag build now **fails** when `DEVELOPER_ID_P12` is missing, rather than quietly
publishing an unsigned app — the README and the cask promise a signed one, and a
release that silently isn't is worse than a release that doesn't happen.
`workflow_dispatch` stays permissive, so that is the way to rehearse the pipeline
or cut a deliberately unsigned build.

CI proves Gatekeeper accepts the bundle (`spctl` must report
`source=Notarized Developer ID`), but the only check that proves the *product*
works is a human one, because it is the one thing CI cannot stage: download the
published zip on a Mac that has never seen this app, drag it to `/Applications`,
and double-click. No right-click, no dialog, no `xattr`.

If that ever regresses, the messaging in README.md, the cask caveats, and the
release-notes footer all have to come back with it.

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
