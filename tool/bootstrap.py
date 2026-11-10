#!/usr/bin/env python3
"""Generate Flutter platform shells and patch LAN permissions; idempotent."""
from __future__ import annotations

import pathlib
import plistlib
import shutil
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
    "android.permission.ACCESS_WIFI_STATE",
    "android.permission.CHANGE_WIFI_STATE",
    "android.permission.CHANGE_NETWORK_STATE",
    "android.permission.NEARBY_WIFI_DEVICES",
    "android.permission.ACCESS_FINE_LOCATION",
    "android.permission.CAMERA",
    "android.permission.REQUEST_INSTALL_PACKAGES",
):
    if not any(x.attrib.get(f"{{{ns}}}name") == permission
               for x in root.findall("uses-permission")):
        element = ET.Element("uses-permission")
        element.set(f"{{{ns}}}name", permission)
        if permission == "android.permission.NEARBY_WIFI_DEVICES":
            element.set(f"{{{ns}}}usesPermissionFlags", "neverForLocation")
        if permission == "android.permission.ACCESS_FINE_LOCATION":
            element.set(f"{{{ns}}}maxSdkVersion", "32")
        root.insert(0, element)
if not any(element.attrib.get(f"{{{ns}}}name") == "android.hardware.wifi.direct"
           for element in root.findall("uses-feature")):
    feature = ET.Element("uses-feature")
    feature.set(f"{{{ns}}}name", "android.hardware.wifi.direct")
    feature.set(f"{{{ns}}}required", "false")
    root.insert(0, feature)

application = root.find("application")
if application is not None:
    application.set(f"{{{ns}}}usesCleartextTraffic", "true")
    application.set(f"{{{ns}}}label", "ShareM")
    if not any(item.attrib.get(f"{{{ns}}}authorities") ==
               "com.yahia.sharem.sharefiles"
               for item in application.findall("provider")):
        provider = ET.SubElement(application, "provider")
        provider.set(f"{{{ns}}}name", "androidx.core.content.FileProvider")
        provider.set(f"{{{ns}}}authorities", "com.yahia.sharem.sharefiles")
        provider.set(f"{{{ns}}}exported", "false")
        provider.set(f"{{{ns}}}grantUriPermissions", "true")
        metadata = ET.SubElement(provider, "meta-data")
        metadata.set(f"{{{ns}}}name", "android.support.FILE_PROVIDER_PATHS")
        metadata.set(f"{{{ns}}}resource", "@xml/sharem_file_paths")
tree.write(android, encoding="utf-8", xml_declaration=True)
native_source = ROOT / "native/android/MainActivity.kt"
native_target = ROOT / "android/app/src/main/kotlin/com/yahia/sharem/MainActivity.kt"
native_target.parent.mkdir(parents=True, exist_ok=True)
shutil.copy2(native_source, native_target)
update_paths = ROOT / "android/app/src/main/res/xml/sharem_file_paths.xml"
update_paths.parent.mkdir(parents=True, exist_ok=True)
update_paths.write_text(
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<paths xmlns:android="http://schemas.android.com/apk/res/android">\n'
    '  <cache-path name="sharem_updates" path="sharem_updates/" />\n'
    '</paths>\n',
    encoding="utf-8",
)

# Never ship a release signed by a transient CI debug key.
# android/key.properties is created only from private GitHub Actions secrets.
gradle_path = ROOT / "android/app/build.gradle.kts"
if gradle_path.exists():
    gradle = gradle_path.read_text(encoding="utf-8")
    if "sharemKeyPropertiesFile" not in gradle:
        signing = (
            'val sharemKeyPropertiesFile = rootProject.file("key.properties")\n'
            'val sharemKeyProperties = java.util.Properties().apply {\n'
            '  if (sharemKeyPropertiesFile.exists()) {\n'
            '    load(java.io.FileInputStream(sharemKeyPropertiesFile))\n'
            '  }\n'
            '}\n\n'
        )
        gradle = signing + gradle
        gradle = gradle.replace(
            "android {",
            'android {\n'
            '  signingConfigs {\n'
            '    create("sharemRelease") {\n'
            '      if (sharemKeyPropertiesFile.exists()) {\n'
            '        keyAlias = sharemKeyProperties["keyAlias"] as String\n'
            '        keyPassword = sharemKeyProperties["keyPassword"] as String\n'
            '        storePassword = sharemKeyProperties["storePassword"] as String\n'
            '        storeFile = file(sharemKeyProperties["storeFile"] as String)\n'
            '      }\n'
            '    }\n'
            '  }\n',
            1,
        )
        gradle = gradle.replace(
            'signingConfig = signingConfigs.getByName("debug")',
            'signingConfig = if (sharemKeyPropertiesFile.exists()) '
            'signingConfigs.getByName("sharemRelease") else null',
        )
        gradle_path.write_text(gradle, encoding="utf-8")

ios = ROOT / "ios/Runner/Info.plist"
if ios.exists():
    with ios.open("rb") as handle:
        data = plistlib.load(handle)
    data["NSCameraUsageDescription"] = (
        "ShareM scans a QR code to pair with a nearby device."
    )
    data["NSLocalNetworkUsageDescription"] = (
        "ShareM discovers nearby devices and transfers files on your local network."
    )
    data["NSAppTransportSecurity"] = {"NSAllowsLocalNetworking": True}
    data["CFBundleDisplayName"] = "ShareM"
    data["UIFileSharingEnabled"] = True
    data["LSSupportsOpeningDocumentsInPlace"] = True
    with ios.open("wb") as handle:
        plistlib.dump(data, handle)

macos_info = ROOT / "macos/Runner/Info.plist"
if macos_info.exists():
    with macos_info.open("rb") as handle:
        macos_data = plistlib.load(handle)
    macos_data["NSCameraUsageDescription"] = (
        "ShareM uses the camera only to scan device pairing QR codes."
    )
    macos_data["CFBundleDisplayName"] = "ShareM"
    with macos_info.open("wb") as handle:
        plistlib.dump(macos_data, handle)

windows_main = ROOT / "windows/runner/main.cpp"
if windows_main.exists():
    window_source = windows_main.read_text(encoding="utf-8")
    window_source = window_source.replace('L"sharem"', 'L"ShareM"')
    windows_main.write_text(window_source, encoding="utf-8")

linux_app = ROOT / "linux/runner/my_application.cc"
if linux_app.exists():
    linux_source = linux_app.read_text(encoding="utf-8")
    linux_source = linux_source.replace('"sharem"', '"ShareM"')
    linux_app.write_text(linux_source, encoding="utf-8")

for name in ("DebugProfile.entitlements", "Release.entitlements"):
    file = ROOT / "macos/Runner" / name
    if file.exists():
        with file.open("rb") as handle:
            data = plistlib.load(handle)
        data["com.apple.security.network.client"] = True
        data["com.apple.security.network.server"] = True
        data["com.apple.security.device.camera"] = True
        with file.open("wb") as handle:
            plistlib.dump(data, handle)
generated_test = ROOT / "test/widget_test.dart"
if generated_test.exists():
    generated_test.unlink()
print("Platform scaffolding ready.")
