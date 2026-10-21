import base64
import datetime as dt
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("release", Path(__file__).parents[1] / "Tools/apple-release.py")
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseTests(unittest.TestCase):
    def profile(self, bundle="com.jasonmiller.dots"):
        return {
            "UUID": "00000000-0000-0000-0000-000000000001",
            "TeamIdentifier": ["KY3DU2D7QL"],
            "ExpirationDate": dt.datetime(2099, 1, 1),
            "Entitlements": {
                "application-identifier": "KY3DU2D7QL." + bundle,
                "beta-reports-active": True,
                "get-task-allow": False,
                "com.apple.security.application-groups": ["group.com.jasonmiller.dots"],
                "com.apple.developer.icloud-container-identifiers": ["iCloud.com.jasonmiller.dots"],
                "com.apple.developer.icloud-services": ["CloudKit"],
                "com.apple.developer.icloud-container-environment": "Production",
                "aps-environment": "production",
            },
        }

    def test_accepts_distribution_profiles_for_both_targets(self):
        for bundle in release.BUNDLES.values():
            release.validate_profile(self.profile(bundle), bundle, "KY3DU2D7QL")

    def test_rejects_wrong_team_or_bundle(self):
        for field, value in [("TeamIdentifier", ["OTHERTEAM1"]), ("UUID", "../../not-a-profile")]:
            profile = self.profile()
            profile[field] = value
            with self.assertRaises(ValueError):
                release.validate_profile(profile, release.BUNDLES["APP"], "KY3DU2D7QL")
        with self.assertRaisesRegex(ValueError, "explicit App ID"):
            release.validate_profile(self.profile(release.BUNDLES["WIDGET"]), release.BUNDLES["APP"], "KY3DU2D7QL")

    def test_rejects_expired_profile(self):
        profile = self.profile()
        profile["ExpirationDate"] = dt.datetime(2000, 1, 1)
        with self.assertRaisesRegex(ValueError, "expired"):
            release.validate_profile(profile, release.BUNDLES["APP"], "KY3DU2D7QL")

    def test_rejects_development_adhoc_and_enterprise_profiles(self):
        for change in [{"ProvisionedDevices": ["device"]}, {"ProvisionsAllDevices": True},
                       {"Entitlements": dict(self.profile()["Entitlements"], **{"get-task-allow": True})}]:
            profile = dict(self.profile(), **change)
            with self.assertRaisesRegex(ValueError, "App Store distribution"):
                release.validate_profile(profile, release.BUNDLES["APP"], "KY3DU2D7QL")

    def test_rejects_missing_capabilities(self):
        fields = ["com.apple.security.application-groups", "com.apple.developer.icloud-container-identifiers",
                  "com.apple.developer.icloud-services", "com.apple.developer.icloud-container-environment", "aps-environment"]
        for field in fields:
            with self.subTest(field=field):
                profile = self.profile()
                del profile["Entitlements"][field]
                with self.assertRaises(ValueError):
                    release.validate_profile(profile, release.BUNDLES["APP"], "KY3DU2D7QL")

    def test_missing_secrets_fail_before_any_signing_operation(self):
        with patch.dict(os.environ, {}, clear=True), patch.object(release, "run") as command:
            with self.assertRaisesRegex(RuntimeError, "APP_STORE_CONNECT_PRIVATE_KEY"):
                release.prepare()
            command.assert_not_called()

    def test_build_number_uses_highest_existing_number(self):
        self.assertEqual(release.next_build([]), "1")
        self.assertEqual(release.next_build(["9", "2", "10"]), "11")
        self.assertEqual(release.next_build(["2.9.9", "3.0"]), "4")
        with self.assertRaises(ValueError):
            release.next_build(["9999"])

    def test_pagination_preserves_all_builds(self):
        pages = [{"data": [1], "links": {"next": release.API + "/v1/builds?cursor=next"}}, {"data": [2]}]
        with patch.dict(os.environ, {"APPLE_APP_ID": "6825127572"}), patch.object(release, "get", side_effect=pages):
            self.assertEqual(list(release.build_rows()), [1, 2])

    def test_api_credentials_never_sent_to_other_hosts(self):
        for url in ["https://example.com/v1/builds", "//example.com/v1/builds", release.API + ".example.com/builds"]:
            with patch.object(release, "token") as token:
                with self.assertRaises(ValueError):
                    release.get(url)
                token.assert_not_called()

    def test_jwt_has_valid_es256_signature(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp) / "dotlings-signing"
            folder.mkdir()
            key = folder / "AuthKey_TESTKEY123.p8"
            subprocess.run(["openssl", "genpkey", "-algorithm", "EC", "-pkeyopt", "ec_paramgen_curve:prime256v1", "-out", str(key)], check=True, capture_output=True)
            env = {"RUNNER_TEMP": temp, "APP_STORE_CONNECT_KEY_ID": "TESTKEY123", "APP_STORE_CONNECT_ISSUER_ID": "test-issuer"}
            with patch.dict(os.environ, env):
                token = release.token()
            header, payload, raw_signature = token.split(".")
            decode = lambda value: base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))
            self.assertEqual(json.loads(decode(header))["alg"], "ES256")
            self.assertEqual(json.loads(decode(payload))["aud"], "appstoreconnect-v1")
            raw = decode(raw_signature)
            self.assertEqual(len(raw), 64)
            integers = []
            for part in [raw[:32], raw[32:]]:
                part = part.lstrip(b"\x00") or b"\x00"
                if part[0] & 128:
                    part = b"\x00" + part
                integers.append(b"\x02" + bytes([len(part)]) + part)
            body = b"".join(integers)
            signature = Path(temp) / "signature.der"
            signature.write_bytes(b"\x30" + bytes([len(body)]) + body)
            public = Path(temp) / "public.pem"
            subprocess.run(["openssl", "pkey", "-in", str(key), "-pubout", "-out", str(public)], check=True, capture_output=True)
            subprocess.run(["openssl", "dgst", "-sha256", "-verify", str(public), "-signature", str(signature)],
                           input=(header + "." + payload).encode(), check=True, capture_output=True)

    def test_only_valid_apple_processing_is_success(self):
        with tempfile.TemporaryDirectory() as temp:
            previous = Path.cwd()
            os.chdir(temp)
            try:
                Path("build").mkdir()
                env = {"APPLE_BUILD_NUMBER": "3", "APPLE_APP_VERSION": "1.0", "APPLE_APP_ID": "6825127572",
                       "GITHUB_SHA": "commit", "GITHUB_STEP_SUMMARY": str(Path(temp) / "summary.md")}
                for state in ["VALID", "INVALID", "FAILED"]:
                    rows = [{"id": "build-id", "attributes": {"version": "3", "processingState": state}}]
                    with patch.dict(os.environ, env), patch.object(release, "build_rows", return_value=iter(rows)):
                        if state == "VALID":
                            release.wait()
                        else:
                            with self.assertRaisesRegex(RuntimeError, state):
                                release.wait()
                    receipt = json.loads(Path("build/apple-upload-receipt.json").read_text())
                    self.assertEqual(receipt["processing_state"], state)
            finally:
                os.chdir(previous)

    def test_pending_upload_is_retained_without_claiming_success(self):
        with tempfile.TemporaryDirectory() as temp:
            previous = Path.cwd()
            os.chdir(temp)
            try:
                Path("build").mkdir()
                env = {"APPLE_BUILD_NUMBER": "3", "APPLE_APP_VERSION": "1.0", "APPLE_APP_ID": "6825127572", "GITHUB_SHA": "commit"}
                with patch.dict(os.environ, env), patch.object(release, "build_rows", return_value=iter([])), \
                     patch.object(release.time, "monotonic", side_effect=[0, 0, 1201]), patch.object(release.time, "sleep"):
                    with self.assertRaisesRegex(RuntimeError, "Check TestFlight before rerunning"):
                        release.wait()
                receipt = json.loads(Path("build/apple-upload-receipt.json").read_text())
                self.assertTrue(receipt["upload_accepted"])
                self.assertEqual(receipt["processing_state"], "PENDING")
            finally:
                os.chdir(previous)


if __name__ == "__main__":
    unittest.main()
