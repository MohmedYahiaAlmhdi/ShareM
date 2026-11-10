# ShareM

**ShareM** is an Arabic-first Flutter peer-to-peer LAN file sharing app with a teal Material 3 interface. It targets Android, iOS, Windows, macOS and Linux.

**Status: 0.1.0 prototype, not a production-ready alternative to SHAREit/ShareMe.**
The current transport is plain HTTP over local Wi-Fi; **not encrypted**. Use trusted networks only.

## Implemented

- Responsive Arabic RTL dashboard, device browser, history and settings
- UDP broadcast device discovery (when local network allows it)
- Manual receiver connection by IP address and port
- Receiver approval before accepting incoming files
- Multi-file streaming, per-file SHA-256 integrity checking, collision-safe file names
- Progress indicator, outgoing cancellation, local nickname and transfer history
- Incoming files stored in the app's documents/ShareM/Received folder
- GitHub Actions checks including Flutter analysis, tests and Android debug APK

## Not implemented yet

Wi-Fi Direct negotiation, automatic hotspots, QR camera pairing, Bluetooth transfers, encrypted sessions, browser client, folder trees, resume, background transfers, Android file-manager export, system share integration, full real-device testing and store-ready signed releases.

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

## Test a transfer

Open ShareM on two devices on the same Wi-Fi or hotspot; keep both apps open. Select the receiver in the nearby devices list, choose files and approve the incoming offer. If discovery is unavailable, copy the IP:port shown on the receiving device's settings screen and use manual connection.

**Caution:** Browser Wi-Fi sharing and Android-to-iOS direct Wi-Fi pairing are not in v0.1. The app does not access public Android Downloads; incoming items currently go to the app documents folder.

## Project folders

- lib/src/core/transfer_models.dart: transfer models and input validation
- lib/src/core/lan_transfer_service.dart: local discovery, file streaming, consent, integrity and history
- lib/src/ui: responsive Flutter interface
- test: unit tests and LAN protocol checks
- tool/bootstrap.py: native platform scaffolding and permissions
- .github/workflows/flutter.yml: CI and debug APK artifact

## Experimental protocol

UDP broadcast on port 43886 announces JSON device data. Each device runs an ephemeral HTTP service. GET /v1/hello identifies a peer; POST /v1/offer creates a pending request with file sizes and hashes. The sender polls GET /v1/status/{id} for consent and a random token. POST /v1/files/{id}/{index} streams each file to the approved receiver, which validates exact size and SHA-256. The receiver checks the request's source IP and session token.

## Planned priorities

1. Authenticated end-to-end encryption with QR / short authentication string pairing.
2. Native Wi-Fi Direct and hotspot support on compatible Android devices; iOS-native network discovery.
3. Resumable encrypted chunk streams, transfer queue and background service.
4. Phone share-sheet integration and safe file export, desktop packaging.
5. Cross-device tests, performance benchmarks, accessibility and signed releases.

Maintained by Mohmed Yahia Almhdi.
