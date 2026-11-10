#!/usr/bin/env python3
"""Generate Flutter platform shells and patch LAN permissions; idempotent."""
from __future__ import annotations

import pathlib
import plistlib
import subprocess
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parents[1]
subprocess.run(
    ["flutter", "create", "--project-name", "sharem",
     "--org", "com.yahia", "--platforms=android,ios,windows,macos,linux", "."],
    cwd=ROOT, check=True,
)
android = ROOT / "android/app/src/main/AndroidManifest.xml"
tree = ET.parse(android)
root = tree.getroot()
ns = "http://schemas.android.com/apk/res/android"
ET.register_namespace("android", ns)
for permission in (
    "android.permission.INTERNET",
    "android.permission.ACCESS_NETWORK_STATE",
    "android.permission.CHANGE_WIFI_MULTICAST_STATE",
):
    if not any(x.attrib.get(f"{{{ns}}}name") == permission
               for x in root.findall("uses-permission")):
        element = ET.Element("uses-permission")
        element.set(f"{{{ns}}}name", permission)
        root.insert(0, element)
application = root.find("application")
if application is not None:
    application.set(f"{{{ns}}}usesCleartextTraffic", "true")
tree.write(android, encoding="utf-8", xml_declaration=True)

ios = ROOT / "ios/Runner/Info.plist"
if ios.exists():
    with ios.open("rb") as handle:
        data = plistlib.load(handle)
    data["NSLocalNetworkUsageDescription"] = (
        "ShareM discovers nearby devices and transfers files on your local network."
    )
    data["NSAppTransportSecurity"] = {"NSAllowsLocalNetworking": True}
    data["UIFileSharingEnabled"] = True
    data["LSSupportsOpeningDocumentsInPlace"] = True
    with ios.open("wb") as handle:
        plistlib.dump(data, handle)

for name in ("DebugProfile.entitlements", "Release.entitlements"):
    file = ROOT / "macos/Runner" / name
    if file.exists():
        with file.open("rb") as handle:
            data = plistlib.load(handle)
        data["com.apple.security.network.client"] = True
        data["com.apple.security.network.server"] = True
        with file.open("wb") as handle:
            plistlib.dump(data, handle)
generated_test = ROOT / "test/widget_test.dart"
if generated_test.exists():
    generated_test.unlink()
print("Platform scaffolding ready.")
