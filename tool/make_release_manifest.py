#!/usr/bin/env python3
"""Build checked update.json + named APK assets from Flutter's split release APKs."""
import hashlib
import json
import pathlib
import re
import shutil

root = pathlib.Path(__file__).resolve().parents[1]
match = re.search(r"^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$",
                  (root / "pubspec.yaml").read_text(), re.M)
if not match:
    raise SystemExit("Missing valid pubspec version")
version, number = match.group(1), int(match.group(2))
dest = root / "build/sharem_release"
dest.mkdir(parents=True, exist_ok=True)
assets = {}
for abi in ("arm64-v8a", "armeabi-v7a", "x86_64"):
    original = root / "build/app/outputs/flutter-apk" / f"app-{abi}-release.apk"
    if not original.is_file():
        raise SystemExit(f"Missing release APK: {original}")
    name = f"ShareM-v{version}-{abi}.apk"
    target = dest / name
    shutil.copy2(original, target)
    digest = hashlib.sha256(target.read_bytes()).hexdigest()
    assets[abi] = {
        "url": f"https://github.com/MohmedYahiaAlmhdi/ShareM/releases/download/v{version}/{name}",
        "sha256": digest,
        "sizeBytes": target.stat().st_size,
    }
manifest = {
    "version": version,
    "buildNumber": number,
    "notes": "Optimized release APKs and secure SHA-256 checked updates.",
    "android": assets,
}
(dest / "update.json").write_text(
    json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8",
)
print(json.dumps({"version": version, "sizes": {k: v["sizeBytes"] for k, v in assets.items()}}))
