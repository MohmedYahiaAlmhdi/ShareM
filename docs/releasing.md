# ShareM Android release signing and updates

ShareM uses its package ID `com.yahia.sharem` for Android. Updates only install over an older APK if the **signing certificate stays identical** and the version code increases. Keep a permanent backup of the signing keystore.

## Configure signing secrets

Never commit keystores, passwords or key.properties to GitHub. In the repository open **Settings → Secrets and variables → Actions → New repository secret** and add:

- `SHAREM_SIGNING_KEYSTORE_B64`: base64 of the **same permanent** signing keystore.
- `SHAREM_KEYSTORE_PASSWORD`: keystore password.
- `SHAREM_KEY_ALIAS`: key alias.
- `SHAREM_KEY_PASSWORD`: key password.

Generate a keystore **once** on a trusted machine: `keytool -genkeypair -v -keystore sharem-release.jks -alias sharem-release -keyalg RSA -keysize 3072 -validity 10000 -storetype JKS`.

Encode it on Linux: `base64 -w0 sharem-release.jks`; or PowerShell: `[Convert]::ToBase64String([IO.File]::ReadAllBytes("sharem-release.jks"))`.

Keep secure offline backups. If you lose the keystore, you cannot ship in-place updates to the same installation.

## Build and publish

After configuring secrets, choose **Actions → ShareM Signed Android Release → Run workflow** on main. It validates code, builds 3 signed architecture-specific Release APKs, verifies their signatures, generates `update.json` with checksum/size for each APK, and publishes GitHub Release `vX.Y.Z`.

For the next version, increase `version: X.Y.Z+BUILD` in pubspec.yaml and run the release workflow. The app checks `https://github.com/MohmedYahiaAlmhdi/ShareM/releases/latest/download/update.json`, chooses the right CPU ABI, downloads the APK, verifies SHA-256, then asks Android to install it.

**The previously distributed v0.2.0 Debug build cannot be updated in place to a differently signed release.** Back up its app files, uninstall it once, then install the first permanently signed release. Subsequent releases can update without uninstalling if the signing key and package ID remain stable.

### Limitations

Android always needs user confirmation to install; newer Android may require granting ShareM permission to install unknown apps. iOS, macOS, Windows, and Linux require their own signed distributions; an Android APK cannot update them.

ShareM file transfer over HTTP still does not provide end-to-end encryption. Do not use over untrusted LANs.
