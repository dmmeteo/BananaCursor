# Releasing BananaCursor

`release.json` defines the production version, increasing build number, feed, public key, and pinned Sparkle SDK. Keep the Xcode version defaults consistent. Each release must increase both the version and build; record the prior release in `previousVersion` and `previousBuild`.

## Build and package

Use macOS, Xcode, and `uv`. Commit the release inputs before building. Packaging rejects a dirty checkout, a dirty build receipt, mismatched inputs, or a changed executable.

```sh
./scripts/test.sh
./scripts/build.sh
./scripts/package-release.sh
```

The default output is `build/release/<version>/`:

- `BananaCursor.dmg`: drag-to-Applications installer.
- `BananaCursor-<version>-macos.zip`: the exact signed app for Sparkle.
- `appcast.xml`: signed feed with the ZIP enclosure and signature.
- `SHA256SUMS.txt` and `receipt.json`: integrity and build evidence.

The packaging script uses `dmgbuild==1.6.7`, verifies the ZIP and mounted DMG, checks both architectures and strict signatures, and verifies the feed and ZIP with Sparkle's tools. It does not launch, install, upload, or publish anything. Use a fresh `--output` directory when repeating a package.

The release uses free ad-hoc signing without Apple notarization. Do not describe it as Developer ID signed or Apple approved. Users may need the standard [Open Anyway first-launch flow](https://support.apple.com/en-us/102445).

## Signing key

The dedicated login Keychain account is `com.dmmeteo.BananaCursor`. Its public key is pinned in the app and `release.json`. Packaging checks that the account still has the matching public key before signing. Keep an encrypted backup of the signing Keychain under the maintainer's control. Losing or replacing this key breaks updates for installed copies. Never commit a private key or regenerate this account as part of a release.

The SDK cache is verified against the pinned archive SHA-256. `scripts/fetch-sparkle.sh` preserves the framework's symlinks; the complete Sparkle license is bundled before the app is signed.

## Native acceptance

Before publication, install the candidate from its actual disk image in Finder. Check the two icons, drag installation, first launch, theme apply/edit, and the optional helper. Retain an older installed app for a real update test.

To compile a separate updater-enabled test app, use an HTTPS signed acceptance feed that points to the candidate ZIP:

```sh
./scripts/build.sh --version 0.1.1 --build 2 \
  --feed-url https://example.org/acceptance/appcast.xml \
  --derived-data build/AcceptanceA --output build/acceptance/BananaCursor.app
```

This builds the older version from source; it does not relabel a release binary. Never publish the acceptance build as the production release.

Verify manual checks with automatic checks off, late quiet results after switching off, and a real A-to-B install/relaunch. Test a dirty editor with Cancel and with a failed Save: both must keep the draft and prevent installation or Quit. Normal Quit after availability checks must not install anything. A corrupted ZIP or invalid feed signature must fail without replacing the app. Packaging alone does not prove these native behaviors.

## Publish

1. Create the version tag and GitHub release from the verified commit.
2. Upload the DMG, ZIP, checksums, and receipt to that release. Keep the DMG basename `BananaCursor.dmg` so the README's latest-download link stays stable.
3. Confirm the HTTPS ZIP URL and checksums. Copy the generated, verified `appcast.xml` byte for byte to `updates/appcast.xml` on `main`, and publish the feed last. Any XML edit requires signing and verifying it again.
4. Check the public download, production feed, and updater from the installed older app.

The production feed is `https://raw.githubusercontent.com/dmmeteo/BananaCursor/main/updates/appcast.xml`. ZIP URLs use `https://github.com/dmmeteo/BananaCursor/releases/download/v<version>/`. Keep existing release assets unchanged. Version 0.1.0 has no updater and needs one manual DMG installation.
