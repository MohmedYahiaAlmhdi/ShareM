# ShareM

**ShareM** is an Arabic-first Flutter peer-to-peer LAN file sharing app with a teal Material 3 interface. It targets Android, iOS, Windows, macOS and Linux.

**Status: 0.5.0 development prototype, not a production-ready alternative to SHAREit/ShareMe.**
The current transport is plain HTTP over local Wi-Fi; **not encrypted**. Use trusted networks only.

## New ShareM 0.4.0 interface

- Clean, mobile-first teal/cyan ShareMe-style experience with a single prominent Send/Receive choice, six quick file categories, a live animated nearby-device radar, recent activity and minimal navigation
- **Choose files first**, then choose the receiver; if none are connected, QR/Wi-Fi Direct pairing stays available without discarding the chosen files
- The radar displays real discovered peers only; device locations on the radar are decorative and **are not** distance estimates
- Prominent pairing page and quick access to app updates in Settings
- Android/iOS launcher icon is generated from original ShareM branding during the CI build

## Implemented

- Responsive Arabic RTL dashboard, device browser, history and settings
- UDP broadcast device discovery (when local network allows it)
- Manual receiver connection by IP address and port
- **QR pairing:** display device QR, scan with Android/iOS/macOS camera, and verify the encoded device ID against the actual HTTP peer
- **Android Wi-Fi Direct:** native peer discovery, runtime permission request, negotiation, and client connection to the group owner's ShareM TCP endpoint on port 43887
- Receiver approval before accepting incoming files
- Multi-file streaming, per-file SHA-256 integrity checking, collision-safe file names
- Progress indicator, outgoing cancellation, local nickname and transfer history
- Incoming files stored in the app's documents/ShareM/Received folder, with OS share-sheet export for received files where supported
- In-app Android APK update checker with ABI selection and SHA-256 download verification
- Android installer launches from an app-private APK via FileProvider, with OS permission and confirmation
- GitHub Actions checks and separate signed Release workflow with a stable signing key from repository secrets

## Not implemented yet

Automatic hotspot setup, AirDrop interoperability, Bluetooth transfers, encrypted sessions, browser client, folder trees, resume, background transfers, Android public Downloads auto-save, full real-device testing and commercial store readiness.

## Run the app

Install Flutter stable, native build tools, and Python 3.

~~~bash
git clone https://github.com/MohmedYahiaAlmhdi/ShareM.git
cd ShareM
python tool/bootstrap.py
flutter pub get
flutter analyze
flutter test
flutter run
~~~

On Linux/macOS use python3 if python is unavailable. The bootstrap command creates native platform folders using Flutter and applies required local-network permissions and entitlements. Those generated folders are gitignored in this prototype.

For Android:

~~~bash
flutter build apk --debug
~~~

## Release builds and in-app updates

Version **0.3.0+3** introduces Android update checking under **الإعدادات → تحديثات ShareM**. It checks the latest published GitHub Release's update.json, chooses a signed APK for the CPU ABI, validates size and SHA-256, and invokes Android's installer (requires user confirmation).

To produce installable **signed release APKs** instead of debug builds, configure the four permanent signing secrets documented in [docs/releasing.md](docs/releasing.md). Then run **ShareM Signed Android Release** in GitHub Actions; this builds optimized split APKs for `arm64-v8a`, `armeabi-v7a`, and `x86_64`, and publishes matching update.json.

Do not publish with an ephemeral debug key: updates must use the SAME release signing certificate for every subsequent version. The old debug build and a permanently signed release build require a **one-time reinstall**; back up incoming files before removing the debug app.

Important: iOS, macOS, Windows, and Linux require separate platform-specific signed installers; APK auto-update is Android-only.

## QR pairing
Open **الاقتران** on both devices. On the receiver choose **عرض رمز جهازي**; on the sender choose **مسح QR**. Both must already be on the same LAN or established Wi-Fi Direct group. The QR contains only a local IP, port, temporary application ID and nickname (no password/token). A scanned QR is *not* an authenticated cryptographic identity. Windows and Linux use paste-QR-data or manual IP instead of camera scanning.

## Android Wi-Fi Direct
1. Install ShareM on two Android phones that support Wi-Fi P2P; open both apps.
2. Enable Wi-Fi and location services (where required by Android).
3. On both devices navigate to **الاقتران**, grant the **Nearby Wi-Fi Devices** permission (Android 13+) or location permission on earlier Android when asked, and tap **بحث**.
4. Tap **اتصال** beside the other phone. Approve any system confirmation; Android negotiates the P2P group.
5. The initiating client attempts to reach the group owner at its P2P address on TCP port **43887**. Then choose that device in the ShareM nearby list and transfer. The group owner must keep ShareM open.
6. If the connection fails, verify Android support, permissions and Wi-Fi; re-run discovery. A rare port collision may cause ShareM to choose a different TCP port, in which case the automatic Wi-Fi Direct endpoint will not be reachable; use QR/manual connection if the network supports it.

**System limitations:** Android and iOS do not expose an identical native Wi-Fi Direct API. ShareM does not provide cross-platform Wi-Fi Direct interoperability, automatic mobile hotspot setup or guarantees that Wi-Fi Direct works on every Android ROM/hardware. Real-device confirmation is required.

## Test a transfer

Open ShareM on two devices on the same Wi-Fi or hotspot; keep both apps open. Select the receiver in the nearby devices list, choose files and approve the incoming offer. If discovery is unavailable, copy the IP:port shown on the receiving device's settings screen and use manual connection.

**Caution:** Browser Wi-Fi sharing and Android-to-iOS direct Wi-Fi pairing are not in v0.1. The app does not access public Android Downloads; incoming items currently go to the app documents folder.

## Project folders

- lib/src/core/transfer_models.dart: transfer models and input validation
- lib/src/core/lan_transfer_service.dart: local discovery, file streaming, consent, integrity and history
- lib/src/core/qr_pairing.dart: versioned validated QR payload
- lib/src/core/wifi_direct_service.dart: Flutter MethodChannel/EventChannel bridge for Android Wi-Fi P2P
- lib/src/ui/pairing_page.dart: QR generation/scanning and Wi-Fi Direct peer list
- native/android/MainActivity.kt: native WifiP2pManager runtime permissions, discovery and connection events
- lib/src/ui: responsive Flutter interface
- test: unit tests and LAN protocol checks
- tool/bootstrap.py: native platform scaffolding and permissions
- .github/workflows/flutter.yml: CI and debug APK artifact

## Experimental protocol

UDP broadcast on port 43886 announces JSON device data. Each device tries a fixed TCP HTTP listener on **43887** (falls back to ephemeral when occupied). GET /v1/hello identifies a peer; POST /v1/offer creates a pending request with file sizes and hashes. The sender polls GET /v1/status/{id} for consent and a random token. POST /v1/files/{id}/{index} streams each file to the approved receiver, which validates exact size and SHA-256. The receiver checks the request's source IP and session token.

## Planned priorities

1. Authenticated end-to-end encryption with QR / short authentication string verification (current QR is discovery-only).
2. Native Wi-Fi Direct and hotspot support on compatible Android devices; iOS-native network discovery.
3. Resumable encrypted chunk streams, transfer queue and background service.
4. Phone share-sheet integration and safe file export, desktop packaging.
5. Cross-device tests, performance benchmarks, accessibility and signed releases.

Maintained by Mohmed Yahia Almhdi.
