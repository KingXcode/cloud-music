#!/usr/bin/env python3
"""Build an updater manifest from verified package outputs, never a guessed tag.

GitHub supplies an independent SHA-256 digest for every uploaded release asset.
The application cross-checks that digest, this manifest and the downloaded bytes.
This is integrity protection; publisher signing is still enforced by the OS.
"""
import argparse
import hashlib
import json
import pathlib
import re


def create_manifest(directory: pathlib.Path, tag: str, android_only: bool = False):
    match = re.fullmatch(r"v(\d+\.\d+\.\d+)(?:-[A-Za-z0-9.-]+)?", tag)
    if not match:
        raise ValueError("Invalid release tag")
    android = (directory / "android-package.txt").read_text()
    package = re.search(r"package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'", android)
    if not package or package[1] != "dev.cloudmusic.cloud_music":
        raise ValueError("Unexpected Android package")
    build, version = package[2], package[3]
    if version != match[1] or not re.fullmatch(r"[1-9]\d{0,8}", build):
        raise ValueError("APK version/build must match the release tag")
    artifacts = {}

    def artifact(platform, name, architectures):
        path = directory / name
        if not path.is_file() or path.stat().st_size <= 0:
            raise ValueError(f"Missing package: {name}")
        with path.open("rb") as stream:
            digest = hashlib.file_digest(stream, "sha256").hexdigest()
        artifacts[platform] = {
            "name": name,
            "size": path.stat().st_size,
            "sha256": digest,
            "architectures": architectures,
        }

    # Universal release build is required; do not advertise absent ABIs.
    abi = re.search(r"native-code:\s*(.+)", android)
    mapping = {"armeabi-v7a": "arm", "arm64-v8a": "arm64", "x86_64": "x64"}
    architectures = [mapping[a] for a in re.findall(r"'([^']+)'", abi[1] if abi else "") if a in mapping]
    if set(architectures) != {"arm", "arm64", "x64"}:
        raise ValueError("Expected verified universal Android APK")
    artifact("android", "cloud-music-android-test-signed.apk", architectures)
    if not android_only:
        mac = json.loads((directory / "macos-version.json").read_text())
        if mac["version"] != version or str(mac["build"]) != build:
            raise ValueError("Android and macOS versions must match")
        raw_arch = (directory / "macos-architectures.txt").read_text().split()
        if not raw_arch or not set(raw_arch) <= {"arm64", "x86_64"}:
            raise ValueError("Unsupported macOS architectures")
        artifact("macos", "cloud-music-macos-unsigned.dmg", ["x64" if a == "x86_64" else a for a in raw_arch])
    manifest = {"schema": 1, "version": version, "build": build, "artifacts": artifacts}
    (directory / "update-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", type=pathlib.Path)
    parser.add_argument("tag")
    parser.add_argument("--android-only", action="store_true")
    args = parser.parse_args()
    create_manifest(args.directory, args.tag, args.android_only)
