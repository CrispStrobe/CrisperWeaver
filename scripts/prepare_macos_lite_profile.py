#!/usr/bin/env python3
"""Reuse CI's signing certificate to prepare a Lite MAC_APP_STORE profile.

May register the Lite bundle ID and create its profile. Never creates, revokes,
or deletes certificates, never creates an app record, and never uploads builds.
"""

import argparse
import base64
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, utils

API_ROOT = "https://api.appstoreconnect.apple.com"
TEAM_ID = "N9XSJ4M3GT"
LITE_BUNDLE_ID = "com.crispstrobe.crisperweaver.lite"


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


class AppleApi:
    def __init__(self, key_path, key_id, issuer_id):
        self.key = serialization.load_pem_private_key(Path(key_path).read_bytes(), None)
        self.key_id = key_id
        self.issuer_id = issuer_id

    def token(self):
        now = int(time.time())
        header = {"alg": "ES256", "kid": self.key_id, "typ": "JWT"}
        claims = {"iss": self.issuer_id, "iat": now, "exp": now + 600,
                  "aud": "appstoreconnect-v1"}
        signing = ".".join(b64url(json.dumps(x, separators=(",", ":")).encode())
                           for x in (header, claims))
        r, s = utils.decode_dss_signature(self.key.sign(signing.encode(), ec.ECDSA(hashes.SHA256())))
        return signing + "." + b64url(r.to_bytes(32, "big") + s.to_bytes(32, "big"))

    def request(self, path, method="GET", payload=None):
        url = path if path.startswith("https://") else API_ROOT + path
        if urllib.parse.urlparse(url).netloc != "api.appstoreconnect.apple.com":
            raise RuntimeError("Refusing to send Apple credentials to another host")
        request = urllib.request.Request(url, method=method,
            headers={"Authorization": "Bearer " + self.token(), "Content-Type": "application/json"},
            data=None if payload is None else json.dumps(payload).encode())
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            details = json.loads(error.read()).get("errors", [])
            # Print API error details, never authentication headers or keys.
            raise RuntimeError(f"Apple API {error.code}: " + "; ".join(
                f"{item.get('code')}: {item.get('detail')}" for item in details)) from None

    def collection(self, path, **query):
        path += "?" + urllib.parse.urlencode({"limit": 200, **query})
        while path:
            response = self.request(path)
            yield from response["data"]
            path = response.get("links", {}).get("next")


def signing_fingerprints(profile_bytes, keychain_identities):
    profile = plistlib.loads(profile_bytes)
    expected = TEAM_ID + ".com.crispstrobe.crisperweaver"
    if profile["Entitlements"].get("com.apple.application-identifier") != expected:
        raise RuntimeError("Source provisioning profile is not the full CrisperWeaver app")
    valid_identities = set(re.findall(r"\b[0-9A-F]{40}\b", keychain_identities.upper()))
    hashes_in_profile = {hashlib.sha1(cert).hexdigest().upper()
                         for cert in profile["DeveloperCertificates"]}
    matching = valid_identities & hashes_in_profile
    if not matching:
        raise RuntimeError("No valid CI signing identity matches the source profile")
    return matching


def future_date(value):
    return datetime.fromisoformat(value.replace("Z", "+00:00")) > datetime.now(timezone.utc)


def prepare(api, fingerprints):
    certificates = [cert for cert in api.collection("/v1/certificates")
        if cert["attributes"]["certificateType"] in {"DISTRIBUTION", "MAC_APP_DISTRIBUTION"}
        and future_date(cert["attributes"]["expirationDate"])
        and hashlib.sha1(base64.b64decode(cert["attributes"]["certificateContent"])).hexdigest().upper()
            in fingerprints]
    if not certificates:
        raise RuntimeError("CI's existing Distribution certificate is not active in Apple Developer")
    # All selected certificates have private keys already present in this CI keychain.
    cert_ids = {cert["id"] for cert in certificates}
    bundles = list(api.collection("/v1/bundleIds", **{"filter[identifier]": LITE_BUNDLE_ID}))
    if bundles:
        bundle = bundles[0]
    else:
        bundle = api.request("/v1/bundleIds", "POST", {"data": {"type": "bundleIds", "attributes": {
            "identifier": LITE_BUNDLE_ID, "name": "CrisperWeaver Lite", "platform": "MAC_OS"}}})["data"]
        print("Registered Lite bundle ID:", bundle["id"])
    if bundle["attributes"].get("seedId") != TEAM_ID:
        raise RuntimeError("Lite bundle ID belongs to an unexpected team")
    for profile in api.collection("/v1/profiles", **{"filter[profileType]": "MAC_APP_STORE"}):
        attrs = profile["attributes"]
        if (not attrs["name"].startswith("CrisperWeaver Lite")
                or attrs["profileState"] != "ACTIVE" or not future_date(attrs["expirationDate"])):
            continue
        related_bundle = api.request(f"/v1/profiles/{profile['id']}/bundleId")["data"]
        related_certs = api.request(f"/v1/profiles/{profile['id']}/certificates")["data"]
        if related_bundle["id"] == bundle["id"] and cert_ids & {cert["id"] for cert in related_certs}:
            print("Reusing Lite profile:", profile["id"])
            return profile
    profile = api.request("/v1/profiles", "POST", {"data": {
        "type": "profiles", "attributes": {"name": "CrisperWeaver Lite Mac App Store CI",
            "profileType": "MAC_APP_STORE"}, "relationships": {
            "bundleId": {"data": {"type": "bundleIds", "id": bundle["id"]}},
            "certificates": {"data": [{"type": "certificates", "id": cert_id}
                for cert_id in sorted(cert_ids)]}}}})["data"]
    print("Created Lite profile:", profile["id"], "using existing Distribution certificate(s)")
    return profile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--key", required=True)
    parser.add_argument("--source-profile", required=True)
    parser.add_argument("--keychain", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--key-id", default="9RMU3C7422")
    parser.add_argument("--issuer-id", default="5f618ba3-98ef-42ad-835c-fbbef6c76cf5")
    args = parser.parse_args()
    source = subprocess.check_output(["security", "cms", "-D", "-i", args.source_profile])
    identities = subprocess.check_output(["security", "find-identity", "-v", "-p", "codesigning",
        args.keychain], text=True)
    fingerprints = signing_fingerprints(source, identities)
    api = AppleApi(args.key, args.key_id, args.issuer_id)
    profile = prepare(api, fingerprints)
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    with os.fdopen(os.open(output, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "wb") as file:
        file.write(base64.b64decode(profile["attributes"]["profileContent"]))
    print("Lite profile written; no certificates changed, no app record or build submitted")


if __name__ == "__main__":
    main()
