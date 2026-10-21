"""Prepare ephemeral signing files and track this build through App Store Connect."""
import base64
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

SECRETS = (
    "APP_STORE_CONNECT_KEY_ID", "APP_STORE_CONNECT_ISSUER_ID",
    "APP_STORE_CONNECT_PRIVATE_KEY", "BUILD_CERTIFICATE_BASE64", "P12_PASSWORD",
    "APP_PROVISION_PROFILE_BASE64", "WIDGET_PROVISION_PROFILE_BASE64",
)
BUNDLES = {"APP": "com.jasonmiller.dots", "WIDGET": "com.jasonmiller.dots.widget"}
API = "https://api.appstoreconnect.apple.com"


def run(*args, **kwargs):
    result = subprocess.run(args, capture_output=True, **kwargs)
    if result.returncode:
        # Never echo subprocess arguments or credential contents into Actions logs.
        raise RuntimeError(f"{args[0]} failed while preparing or verifying signing")
    return result.stdout


def signing_dir():
    return Path(os.environ["RUNNER_TEMP"]) / "dotlings-signing"


def private_file(path, data):
    path.write_bytes(data)
    path.chmod(0o600)


def allows(value, expected, wildcard=False):
    # Profiles list allowed values; signed app entitlements select one of those values.
    values = [value] if isinstance(value, str) else value if isinstance(value, list) else []
    return expected in values or (wildcard and "*" in values)


def validate_profile(profile, bundle, team, now=None):
    now = now or dt.datetime.now(dt.timezone.utc).replace(tzinfo=None)
    entitlements = profile.get("Entitlements", {})
    if team not in profile.get("TeamIdentifier", []):
        raise ValueError(f"{bundle}: provisioning profile belongs to a different Apple team")
    if entitlements.get("application-identifier") != f"{team}.{bundle}":
        raise ValueError(f"{bundle}: provisioning profile has the wrong explicit App ID")
    if not re.fullmatch(r"[A-Fa-f0-9-]{36}", profile.get("UUID", "")):
        raise ValueError(f"{bundle}: provisioning profile has no valid UUID")
    if profile.get("ExpirationDate", dt.datetime.min) <= now:
        raise ValueError(f"{bundle}: provisioning profile has expired")
    if (profile.get("ProvisionedDevices") is not None or profile.get("ProvisionsAllDevices")
            or entitlements.get("get-task-allow") or not entitlements.get("beta-reports-active")):
        raise ValueError(f"{bundle}: use an App Store distribution profile, not development/ad hoc")
    if "group.com.jasonmiller.dots" not in entitlements.get("com.apple.security.application-groups", []):
        raise ValueError(f"{bundle}: provisioning profile is missing the Dotlings App Group")
    if "iCloud.com.jasonmiller.dots" not in entitlements.get("com.apple.developer.icloud-container-identifiers", []):
        raise ValueError(f"{bundle}: provisioning profile is missing the Dotlings iCloud container")
    if not allows(entitlements.get("com.apple.developer.icloud-container-environment"), "Production"):
        raise ValueError(f"{bundle}: provisioning profile must allow production iCloud")
    if not allows(entitlements.get("com.apple.developer.icloud-services"), "CloudKit", wildcard=True):
        raise ValueError(f"{bundle}: provisioning profile is missing CloudKit")
    if bundle == BUNDLES["APP"] and entitlements.get("aps-environment") != "production":
        raise ValueError(f"{bundle}: provisioning profile must enable production push notifications")


def prepare():
    missing = [name for name in SECRETS if not os.environ.get(name)]
    if missing:
        raise RuntimeError("Add these GitHub Actions repository secrets before uploading: " + ", ".join(missing))
    key_id = os.environ["APP_STORE_CONNECT_KEY_ID"]
    if not re.fullmatch(r"[A-Za-z0-9]+", key_id):
        raise ValueError("Invalid App Store Connect key ID")
    folder = signing_dir()
    folder.mkdir(mode=0o700, parents=True, exist_ok=True)
    team = os.environ["APPLE_TEAM_ID"]
    private_file(folder / f"AuthKey_{key_id}.p8", os.environ["APP_STORE_CONNECT_PRIVATE_KEY"].replace("\\n", "\n").encode())
    run("openssl", "pkey", "-in", str(folder / f"AuthKey_{key_id}.p8"), "-noout")
    profiles = {}
    certificate_sets = []
    for label, bundle in BUNDLES.items():
        raw = base64.b64decode("".join(os.environ[f"{label}_PROVISION_PROFILE_BASE64"].split()), validate=True)
        path = folder / f"{label}.mobileprovision"
        private_file(path, raw)
        profile = plistlib.loads(run("security", "cms", "-D", "-i", str(path)))
        validate_profile(profile, bundle, team)
        profiles[bundle] = profile["UUID"]
        certificate_sets.append({hashlib.sha256(cert).digest() for cert in profile["DeveloperCertificates"]})
        # Xcode 16+ uses UserData; retain the legacy path for Xcode tooling compatibility.
        for relative in ["Developer/Xcode/UserData/Provisioning Profiles", "MobileDevice/Provisioning Profiles"]:
            destination = Path.home() / "Library" / relative
            destination.mkdir(parents=True, exist_ok=True)
            private_file(destination / f'{profile["UUID"]}.mobileprovision', raw)
        private_file(folder / "profiles.json", json.dumps(profiles).encode())
    p12 = base64.b64decode("".join(os.environ["BUILD_CERTIFICATE_BASE64"].split()), validate=True)
    private_file(folder / "distribution.p12", p12)
    password = base64.b64encode(os.urandom(32)).decode()
    keychain = str(folder / "distribution.keychain-db")
    run("security", "create-keychain", "-p", password, keychain)
    run("security", "set-keychain-settings", "-lut", "21600", keychain)
    run("security", "unlock-keychain", "-p", password, keychain)
    run("security", "import", str(folder / "distribution.p12"), "-P", os.environ["P12_PASSWORD"],
        "-A", "-t", "cert", "-f", "pkcs12", "-k", keychain)
    run("security", "set-key-partition-list", "-S", "apple-tool:,apple:,codesign:", "-s", "-k", password, keychain)
    old_list = run("security", "list-keychains", "-d", "user").decode()
    original = re.findall(r'"([^"]+)"', old_list)
    run("security", "list-keychains", "-d", "user", "-s", keychain, *original)
    pem = run("security", "find-certificate", "-a", "-p", keychain).decode()
    installed = {hashlib.sha256(base64.b64decode(body)).digest()
                 for body in re.findall(r"-----BEGIN CERTIFICATE-----\s*(.*?)\s*-----END CERTIFICATE-----", pem, re.S)}
    if not all(installed & allowed for allowed in certificate_sets):
        raise ValueError("The distribution certificate does not match both provisioning profiles")
    if b"0 valid identities found" in run("security", "find-identity", "-v", "-p", "codesigning", keychain):
        raise ValueError("The .p12 must include a valid signing certificate and its private key")
    options = {"method": "app-store-connect", "destination": "export", "teamID": team,
               "signingStyle": "manual", "signingCertificate": "Apple Distribution",
               "provisioningProfiles": profiles, "iCloudContainerEnvironment": "Production",
               "manageAppVersionAndBuildNumber": False, "uploadSymbols": True, "stripSwiftSymbols": True}
    private_file(folder / "ExportOptions.plist", plistlib.dumps(options))
    print("Validated distribution credentials for Dotlings and its widget")


def jose_signature(der):
    # OpenSSL returns ASN.1 DER; ES256 JWTs require fixed-width r || s.
    if len(der) < 8 or der[0] != 0x30 or der[1] != len(der) - 2:
        raise ValueError("Invalid ES256 signature")
    values, offset = [], 2
    for _ in range(2):
        if der[offset] != 0x02:
            raise ValueError("Invalid ES256 integer")
        length = der[offset + 1]
        value = der[offset + 2:offset + 2 + length]
        if len(value) != length:
            raise ValueError("Truncated ES256 integer")
        values.append(int.from_bytes(value, "big").to_bytes(32, "big"))
        offset += 2 + length
    if offset != len(der):
        raise ValueError("Unexpected ES256 signature bytes")
    return b"".join(values)


def token():
    def encode(value):
        return base64.urlsafe_b64encode(value).rstrip(b"=")
    now = int(time.time())
    header = {"alg": "ES256", "kid": os.environ["APP_STORE_CONNECT_KEY_ID"], "typ": "JWT"}
    payload = {"iss": os.environ["APP_STORE_CONNECT_ISSUER_ID"], "iat": now - 20,
               "exp": now + 600, "aud": "appstoreconnect-v1"}
    message = encode(json.dumps(header).encode()) + b"." + encode(json.dumps(payload).encode())
    key = signing_dir() / f'AuthKey_{header["kid"]}.p8'
    signature = run("openssl", "dgst", "-sha256", "-sign", str(key), input=message)
    return (message + b"." + encode(jose_signature(signature))).decode()


def get(path):
    if path.startswith("/") and not path.startswith("//"):
        url = API + path
    elif path.startswith(API + "/"):
        url = path
    else:
        raise ValueError("Unexpected App Store Connect pagination URL")
    request = urllib.request.Request(url, headers={"Authorization": "Bearer " + token()})
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        raise RuntimeError(f"Apple API returned HTTP {error.code}; check the API key's access to Dotlings") from None


def build_rows():
    query = urllib.parse.urlencode({"filter[app]": os.environ["APPLE_APP_ID"], "limit": 200})
    path = "/v1/builds?" + query
    while path:
        page = get(path)
        yield from page["data"]
        path = page.get("links", {}).get("next")


def next_build(versions):
    components = [int(version.split(".")[0]) for version in versions]
    number = max(components, default=0) + 1
    if number > 9999:
        raise ValueError("Existing build numbers exceed the supported automatic range; choose a build-number strategy before uploading")
    return str(number)


def number():
    # Check app access before spending time on the archive, then avoid existing build numbers.
    app = get("/v1/apps/" + os.environ["APPLE_APP_ID"])["data"]
    if app["attributes"]["bundleId"] != BUNDLES["APP"]:
        raise ValueError("APPLE_APP_ID points to a different app")
    value = next_build([row["attributes"]["version"] for row in build_rows()])
    with open(os.environ["GITHUB_ENV"], "a") as handle:
        handle.write(f"APPLE_BUILD_NUMBER={value}\n")
    print(f"Building Dotlings {os.environ['APPLE_APP_VERSION']} ({value})")


def verify():
    app = Path("build/Dots.xcarchive/Products/Applications/Dots.app")
    for bundle, identifier in [(app, BUNDLES["APP"]), (app / "PlugIns/DotsWidget.appex", BUNDLES["WIDGET"])]:
        info = plistlib.loads((bundle / "Info.plist").read_bytes())
        for key, expected in [("CFBundleIdentifier", identifier), ("CFBundleVersion", os.environ["APPLE_BUILD_NUMBER"]),
                              ("CFBundleShortVersionString", os.environ["APPLE_APP_VERSION"])]:
            if info.get(key) != expected:
                raise ValueError(f"{identifier}: unexpected {key}")
        entitlements = plistlib.loads(run("codesign", "-d", "--entitlements", ":-", str(bundle)))
        if entitlements.get("com.apple.developer.icloud-container-environment") != "Production":
            raise ValueError(f"{identifier}: signed build is not using production iCloud")
        if identifier == BUNDLES["APP"] and entitlements.get("aps-environment") != "production":
            raise ValueError("The signed app is not using production push notifications")
        run("codesign", "--verify", "--strict", str(bundle))
    print("Verified signed app/widget identifiers, versions and production entitlements")


def wait():
    deadline = time.monotonic() + 1200
    value = os.environ["APPLE_BUILD_NUMBER"]
    receipt = {"app_id": os.environ["APPLE_APP_ID"], "version": os.environ["APPLE_APP_VERSION"],
               "build_number": value, "commit": os.environ["GITHUB_SHA"], "upload_accepted": True,
               "processing_state": "PENDING"}
    path = Path("build/apple-upload-receipt.json")
    path.write_text(json.dumps(receipt, indent=2) + "\n")
    while time.monotonic() < deadline:
        matches = [row for row in build_rows() if row["attributes"]["version"] == value]
        if matches:
            build = matches[0]
            state = build["attributes"]["processingState"]
            receipt.update(build_id=build["id"], processing_state=state)
            path.write_text(json.dumps(receipt, indent=2) + "\n")
            if state == "VALID":
                print(f"Apple processed Dotlings {receipt['version']} ({value}); available in App Store Connect")
                with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as summary:
                    summary.write(f"## Dotlings uploaded\n\nVersion {receipt['version']}, build {value}. Apple processing: VALID.\n\n[Open TestFlight](https://appstoreconnect.apple.com/apps/{receipt['app_id']}/testflight/ios)\n\nApp Review submission and public release remain manual.\n")
                return
            if state in ("FAILED", "INVALID"):
                raise RuntimeError(f"Apple accepted the upload but processing ended as {state}; see App Store Connect")
        time.sleep(30)
    path.write_text(json.dumps(receipt, indent=2) + "\n")
    raise RuntimeError("Apple accepted the upload; processing is still pending. Check TestFlight before rerunning the upload")


def cleanup():
    folder = signing_dir()
    if (folder / "profiles.json").exists():
        for uuid in json.loads((folder / "profiles.json").read_text()).values():
            if re.fullmatch(r"[A-Fa-f0-9-]{36}", uuid):
                for relative in ["Developer/Xcode/UserData/Provisioning Profiles", "MobileDevice/Provisioning Profiles"]:
                    (Path.home() / "Library" / relative / f"{uuid}.mobileprovision").unlink(missing_ok=True)
    keychain = folder / "distribution.keychain-db"
    try:
        if keychain.exists():
            run("security", "delete-keychain", str(keychain))
    finally:
        shutil.rmtree(folder, ignore_errors=True)


if __name__ == "__main__":
    try:
        {"prepare": prepare, "number": number, "verify": verify, "wait": wait, "cleanup": cleanup}[sys.argv[1]]()
    except (RuntimeError, ValueError, KeyError) as error:
        print(f"::error::{error}", file=sys.stderr)
        sys.exit(1)
