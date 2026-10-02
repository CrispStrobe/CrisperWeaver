import base64
from datetime import datetime, timedelta, timezone
import hashlib
import importlib.util
from pathlib import Path
import plistlib
import unittest

spec = importlib.util.spec_from_file_location("lite_profile",
    Path(__file__).resolve().parents[1] / "scripts/prepare_macos_lite_profile.py")
profile_tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(profile_tool)

CERT_BYTES = b"existing CI certificate"
FINGERPRINT = hashlib.sha1(CERT_BYTES).hexdigest().upper()
EXPIRY = (datetime.now(timezone.utc) + timedelta(days=30)).isoformat()


class FakeApi:
    def __init__(self, *, existing_bundle=True, existing_profile=False, matching_cert=True):
        self.writes = []
        self.existing_bundle = existing_bundle
        self.existing_profile = existing_profile
        self.matching_cert = matching_cert

    def collection(self, path, **query):
        if path == "/v1/certificates":
            return [{"id": "ci-cert", "attributes": {"certificateType": "DISTRIBUTION",
                "expirationDate": EXPIRY,
                "certificateContent": base64.b64encode(CERT_BYTES if self.matching_cert else b"other cert").decode()}}]
        if path == "/v1/bundleIds":
            return [{"id": "lite-bundle", "attributes": {"seedId": profile_tool.TEAM_ID}}] if self.existing_bundle else []
        if path == "/v1/profiles":
            return [{"id": "reusable-profile", "attributes": {"name": "CrisperWeaver Lite Mac App Store CI",
                "profileState": "ACTIVE", "expirationDate": EXPIRY, "profileContent": ""}}] if self.existing_profile else []
        raise AssertionError(path)

    def request(self, path, method="GET", payload=None):
        if method == "POST":
            self.writes.append((path, payload))
            if path == "/v1/bundleIds":
                return {"data": {"id": "lite-bundle", "attributes": {"seedId": profile_tool.TEAM_ID}}}
            if path == "/v1/profiles":
                return {"data": {"id": "new-profile", "attributes": {"profileContent": ""}}}
            raise AssertionError("Unexpected Apple mutation: " + path)
        if path.endswith("/bundleId"):
            return {"data": {"id": "lite-bundle"}}
        if path.endswith("/certificates"):
            return {"data": [{"id": "ci-cert"}]}
        raise AssertionError(path)


class PrepareLiteProfileTest(unittest.TestCase):
    def test_source_profile_must_match_a_valid_keychain_identity(self):
        source = plistlib.dumps({"Entitlements": {"com.apple.application-identifier":
            profile_tool.TEAM_ID + ".com.crispstrobe.crisperweaver"}, "DeveloperCertificates": [CERT_BYTES]})
        self.assertEqual(profile_tool.signing_fingerprints(source, FINGERPRINT), {FINGERPRINT})
        with self.assertRaisesRegex(RuntimeError, "No valid CI signing identity"):
            profile_tool.signing_fingerprints(source, "")

    def test_missing_matching_active_certificate_stops_before_any_write(self):
        api = FakeApi(matching_cert=False)
        with self.assertRaisesRegex(RuntimeError, "existing Distribution certificate"):
            profile_tool.prepare(api, {FINGERPRINT})
        self.assertEqual(api.writes, [])

    def test_existing_profile_is_reused_without_mutations(self):
        api = FakeApi(existing_profile=True)
        self.assertEqual(profile_tool.prepare(api, {FINGERPRINT})["id"], "reusable-profile")
        self.assertEqual(api.writes, [])

    def test_only_bundle_and_profile_are_created_with_existing_certificate(self):
        api = FakeApi(existing_bundle=False)
        self.assertEqual(profile_tool.prepare(api, {FINGERPRINT})["id"], "new-profile")
        self.assertEqual([path for path, payload in api.writes], ["/v1/bundleIds", "/v1/profiles"])
        relationships = api.writes[1][1]["data"]["relationships"]
        self.assertEqual(relationships["certificates"]["data"], [{"type": "certificates", "id": "ci-cert"}])
        self.assertEqual(relationships["bundleId"]["data"]["id"], "lite-bundle")


if __name__ == "__main__":
    unittest.main()
