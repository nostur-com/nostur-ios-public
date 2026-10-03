import datetime as dt
import importlib.util
import json
from pathlib import Path
import plistlib
import struct
import tempfile
import unittest
import urllib.parse
from unittest.mock import patch
import zipfile

spec = importlib.util.spec_from_file_location("build_ota", Path(__file__).parents[1] / "build-ota.py")
ota = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ota)


class OtaTests(unittest.TestCase):
    def test_host_rejects_credentials_http_and_ambiguous_urls(self):
        for value in ["http://example.com", "https://user:password@example.com", "https://example.com?token=x",
                      "https://example.com/#fragment", "https://example.com/test builds"]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                ota.https_base(value)
        self.assertEqual(ota.https_base("https://example.com/tests/"), "https://example.com/tests")

    def test_install_link_manifest_and_package_are_consistent_and_unique(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            ipa = root / "source.ipa"
            ipa.write_bytes(b"signed package fixture")
            metadata = {"build_id": "12345678", "bundle_id": "nostur.com.Nostur", "version": "1.0",
                        "build_number": "123", "expires": "2027-01-01", "developer_mode": True}
            first = ota.stage_site(ipa, metadata, "https://example.com/test", root / "site")
            second = ota.stage_site(ipa, metadata, "https://example.com/test", root / "site")
            self.assertNotEqual(first["ipa_url"], second["ipa_url"])
            query = urllib.parse.parse_qs(urllib.parse.urlsplit(second["install_url"]).query)
            self.assertEqual(query["url"], [second["manifest_url"]])
            path = urllib.parse.urlsplit(second["manifest_url"]).path.removeprefix("/test/")
            manifest = plistlib.loads((root / "site" / path).read_bytes())["items"][0]
            self.assertEqual(manifest["assets"][0]["url"], second["ipa_url"])
            self.assertEqual(manifest["metadata"]["bundle-version"], "123")
            self.assertEqual((root / "site" / Path(path).parent / "Nostur.ipa").read_bytes(), ipa.read_bytes())
            self.assertEqual(json.loads((root / "site/latest.json").read_text()), second)
            self.assertIn("Developer Mode", (root / "site/index.html").read_text())

    def test_missing_phone_in_any_extension_profile_blocks_package(self):
        with tempfile.TemporaryDirectory() as directory:
            ipa = Path(directory) / "test.ipa"
            binary = struct.pack("<IIIIIIII", 0xFEEDFACF, 0, 0, 0, 1, 24, 0, 0) + struct.pack("<II", 0x1B, 24) + bytes(range(16))
            with zipfile.ZipFile(ipa, "w") as package:
                package.writestr("Payload/Nostur.app/Info.plist", plistlib.dumps({
                    "CFBundleIdentifier": "nostur.com.Nostur", "CFBundleExecutable": "Nostur",
                    "CFBundleShortVersionString": "1.0", "CFBundleVersion": "1"}))
                package.writestr("Payload/Nostur.app/Nostur", binary)
                package.writestr("Payload/Nostur.app/embedded.mobileprovision", b"main")
                package.writestr("Payload/Nostur.app/PlugIns/Share.appex/Info.plist", plistlib.dumps({}))
                package.writestr("Payload/Nostur.app/PlugIns/Share.appex/embedded.mobileprovision", b"extension")
            profile = {"ProvisionedDevices": ["phone"], "ExpirationDate": dt.datetime(2099, 1, 1), "Entitlements": {}}
            wrong_profile = dict(profile, ProvisionedDevices=["someone-else"])
            class Result:
                def __init__(self, data):
                    self.stdout = plistlib.dumps(data)
            with patch.object(ota.subprocess, "run", side_effect=[Result(profile), Result(wrong_profile)]):
                with self.assertRaisesRegex(ValueError, "not included"):
                    ota.inspect_ipa(ipa, "phone")


if __name__ == "__main__":
    unittest.main()
