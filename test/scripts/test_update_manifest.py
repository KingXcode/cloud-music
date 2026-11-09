import importlib.util
import json
import pathlib
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("manifest", pathlib.Path(__file__).parents[2] / "scripts/create_update_manifest.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ManifestTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        (self.root / "android-package.txt").write_text("package: name='dev.cloudmusic.cloud_music' versionCode='8' versionName='0.6.0'\nnative-code: 'arm64-v8a' 'armeabi-v7a' 'x86_64'\n")
        (self.root / "cloud-music-android-test-signed.apk").write_bytes(b"apk test fixture")
        (self.root / "cloud-music-macos-unsigned.dmg").write_bytes(b"dmg test fixture")
        (self.root / "macos-version.json").write_text(json.dumps({"version": "0.6.0", "build": "8"}))
        (self.root / "macos-architectures.txt").write_text("arm64 x86_64\n")

    def test_complete_manifest(self):
        result = module.create_manifest(self.root, "v0.6.0-preview.1")
        self.assertEqual(result["artifacts"]["macos"]["architectures"], ["arm64", "x64"])
        self.assertEqual(len(result["artifacts"]["android"]["sha256"]), 64)

    def test_tag_mismatch(self):
        with self.assertRaises(ValueError):
            module.create_manifest(self.root, "v0.7.0")

    def test_platform_version_mismatch(self):
        (self.root / "macos-version.json").write_text(json.dumps({"version": "0.5.1", "build": "7"}))
        with self.assertRaises(ValueError):
            module.create_manifest(self.root, "v0.6.0")

    def test_missing_package(self):
        (self.root / "cloud-music-macos-unsigned.dmg").unlink()
        with self.assertRaises(ValueError):
            module.create_manifest(self.root, "v0.6.0")

    def test_android_only(self):
        (self.root / "cloud-music-macos-unsigned.dmg").unlink()
        result = module.create_manifest(self.root, "v0.6.0-android-preview.1", True)
        self.assertEqual(list(result["artifacts"]), ["android"])

    def test_reject_non_universal(self):
        p = self.root / "android-package.txt"
        p.write_text(p.read_text().replace(" 'x86_64'", ""))
        with self.assertRaises(ValueError):
            module.create_manifest(self.root, "v0.6.0")


if __name__ == "__main__":
    unittest.main()
