# Architecture and security — ShareM v0.1

## Transport
A shared local Wi-Fi or hotspot TCP connection is the interoperability baseline across Flutter native systems. UDP broadcast is opportunistic discovery, not authenticated identity. Manual IP:port pairing is available. This is not Wi-Fi Direct and does not interoperate automatically with AirDrop or ShareMe.

## Threat model and current protections
- Explicit receiver approval for incoming offers
- SHA-256 expected digest and exact file-size checks
- 192-bit randomly generated per-offer session tokens
- Observed source-IP matching for all transfer calls
- Leaf-only filename sanitization and collision-safe storage
- Delete incomplete or corrupt output upon verification failure

## Critical limitations
HTTP payloads and session tokens are NOT encrypted in v0.1. A malicious or compromised LAN can observe or tamper with traffic. Do not use ShareM for private files on untrusted networks. IP matching is not cryptographic authentication. No benchmark or cross-device compatibility guarantee is claimed.

**Production blockers:** ephemeral X25519+HKDF+AEAD authenticated pairing, SAS/QR confirmation, key rotation, replay protection, receiver transfer cancellation, network retry and resume, app-lifecycle service, rate limits, disk space quota, platform file permissions, Android exports, Bluetooth and native connectivity strategies, plus real device security and load tests.

## OS restrictions
- Corporate Wi-Fi client isolation can block peer access.
- UDP broadcast may be blocked; manual IP remains the fallback.
- iOS requires local network privacy permission.
- Android local HTTP cleartext permission is added by bootstrap.
- iOS Network framework, Android Wi-Fi Direct and BLE support remain future work.


## QR and Android Wi-Fi Direct (prototype)

- QR payload scheme: sharem://pair?v=1&id=<32 hex>&name=<name>&ip=<private IPv4>&port=<port>. Validate private IPv4 and protocol before connecting; confirm deviceId against GET /v1/hello. QRs are NOT secrets or trust credentials.
- Android native bridge: MethodChannel sharem/wifi_direct and EventChannel sharem/wifi_direct/events. WifiP2pManager handles discovery/negotiation; Dart TCP transfers begin only after group formation.
- Android 13+ requires NEARBY_WIFI_DEVICES runtime permission; Android 12 and earlier require location permission for P2P discovery; location mode may be required even on newer devices. Feature is optional on devices.
- A group owner listens on TCP 43887. A client dials groupOwnerAddress:43887; if 43887 is taken and the app binds an ephemeral port instead, Wi-Fi Direct automatic dialing cannot succeed. Provide a manual/QR fallback when possible.
- QR camera scanning is available on Android, iOS and macOS only with mobile_scanner; Windows/Linux accept pasted payload.
- Using Wi-Fi Direct does not imply end-to-end encryption. The current HTTP transport remains plain text, and source-IP + bearer token is not sufficient against attackers on the LAN.
- Device-specific vendor bugs, permissions and firewall rules need hands-on tests on at least two Android phones before claiming Wi-Fi Direct production support.
