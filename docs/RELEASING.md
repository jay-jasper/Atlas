# Releasing Atlas

1. Run both CI scheme suites and `cargo audit`.
2. Regenerate and verify the UniFFI universal library.
3. Install the distribution certificate and, for Store, the matching provisioning profile.
4. Run `./scripts/build_release.sh store` for App Store Connect or `./scripts/build_release.sh direct` for Developer ID distribution. The script creates an archive and exports it under `build/export-<channel>`.
5. For Direct, run `./scripts/notarize_release.sh build/export-direct/Atlas.app <notary-keychain-profile>` to create, submit, staple, and validate a DMG.
6. Publish the direct update package with a manifest containing `version`, HTTPS `package_url`, lowercase `sha256`, and an Ed25519 signature over `version + "\\n" + package_url + "\\n" + sha256`.

Release credentials stay in the CI secret store. Never commit signing certificates, private Ed25519 keys, App Store Connect keys, or notary credentials.
