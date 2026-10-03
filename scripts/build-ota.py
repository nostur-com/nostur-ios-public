#!/usr/bin/env python3
"""Build/export a registered-device IPA and optionally stage an HTTPS install site.

This command never uploads to TestFlight or a server. See docs/iphone-test-builds.md.
"""
import argparse
import datetime as dt
import fcntl
import hashlib
import html
import json
import os
from pathlib import Path
import plistlib
import shutil
import struct
import subprocess
import sys
import tempfile
import urllib.parse
import uuid
import zipfile

ROOT = Path(__file__).resolve().parent.parent


def https_base(value):
    parts = urllib.parse.urlsplit(value)
    if (parts.scheme != "https" or not parts.hostname or parts.username or parts.password
            or parts.query or parts.fragment or any(ord(c) <= 32 for c in value)):
        raise ValueError("The install-site base URL must be HTTPS, without credentials, query or fragment.")
    return value.rstrip("/")


def binary_uuid(data):
    if len(data) < 32 or struct.unpack_from("<I", data)[0] != 0xFEEDFACF:
        raise ValueError("Expected an arm64 Mach-O binary for the build identity.")
    offset = 32
    for _ in range(struct.unpack_from("<I", data, 16)[0]):
        command, size = struct.unpack_from("<II", data, offset)
        if size < 8 or offset + size > len(data):
            raise ValueError("Invalid Mach-O command.")
        if command == 0x1B:
            return data[offset + 8:offset + 24].hex()[:8]
        offset += size
    raise ValueError("The exported app has no Mach-O UUID.")


def run(command, log):
    print(f"Running {command[0]} ({log.name})", flush=True)
    with log.open("w") as output:
        result = subprocess.run(command, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT)
    if result.returncode:
        raise RuntimeError(f"{command[0]} failed; see {log}")


def inspect_ipa(ipa, device_udid):
    with zipfile.ZipFile(ipa) as package:
        roots = [name for name in package.namelist()
                 if name.startswith("Payload/") and name.endswith(".app/Info.plist") and name.count("/") == 2]
        if len(roots) != 1:
            raise ValueError("Expected one main app in the IPA.")
        info = plistlib.loads(package.read(roots[0]))
        app = roots[0].removesuffix("Info.plist")
        binary = app + "Nostur.debug.dylib"
        if binary not in package.namelist():
            binary = app + info["CFBundleExecutable"]
        build_id = binary_uuid(package.read(binary))
        profiles = [name for name in package.namelist() if name.endswith("/embedded.mobileprovision")]
        bundles = [name.removesuffix("Info.plist") for name in package.namelist()
                   if name.endswith((".app/Info.plist", ".appex/Info.plist"))]
        if any(bundle + "embedded.mobileprovision" not in profiles for bundle in bundles):
            raise ValueError("Every app and extension must have a registered-device provisioning profile.")
        if not profiles:
            raise ValueError("The IPA does not contain registered-device provisioning profiles.")
        expirations = []
        developer_mode = False
        with tempfile.TemporaryDirectory(prefix="nostur-ota-profile-") as directory:
            profile_file = Path(directory) / "profile.mobileprovision"
            for name in profiles:
                profile_file.write_bytes(package.read(name))
                decoded = subprocess.run(["security", "cms", "-D", "-i", str(profile_file)],
                                         check=True, capture_output=True).stdout
                profile = plistlib.loads(decoded)
                if device_udid not in profile.get("ProvisionedDevices", []):
                    raise ValueError(f"Your iPhone is not included in the profile for {Path(name).parent.name}.")
                expiry = profile["ExpirationDate"].replace(tzinfo=dt.timezone.utc)
                if expiry <= dt.datetime.now(dt.timezone.utc):
                    raise ValueError("A provisioning profile has expired.")
                expirations.append(expiry)
                developer_mode |= bool(profile.get("Entitlements", {}).get("get-task-allow"))
        return {"build_id": build_id, "bundle_id": info["CFBundleIdentifier"],
                "version": info["CFBundleShortVersionString"], "build_number": info["CFBundleVersion"],
                "expires": min(expirations).isoformat(), "developer_mode": developer_mode}


def atomic_write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_bytes(data)
    os.replace(temporary, path)


def stage_site(ipa, metadata, base_url, site):
    base_url = https_base(base_url)
    # Unique URLs avoid iOS caching an old package/manifest behind the stable page.
    build_key = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + metadata["build_id"] + "-" + uuid.uuid4().hex
    relative = "builds/" + build_key
    directory = site / relative
    directory.mkdir(parents=True)
    shutil.copy2(ipa, directory / "Nostur.ipa")
    ipa_url = base_url + "/" + relative + "/Nostur.ipa"
    manifest_url = base_url + "/" + relative + "/manifest.plist"
    manifest = {"items": [{"assets": [{"kind": "software-package", "url": ipa_url}],
                           "metadata": {"bundle-identifier": metadata["bundle_id"],
                                        "bundle-version": metadata["build_number"],
                                        "kind": "software", "title": "Nostur test " + metadata["build_id"]}}]}
    (directory / "manifest.plist").write_bytes(plistlib.dumps(manifest))
    install_url = "itms-services://?" + urllib.parse.urlencode({"action": "download-manifest", "url": manifest_url})
    metadata = dict(metadata, ipa_sha256=hashlib.sha256(ipa.read_bytes()).hexdigest(),
                    ipa_url=ipa_url, manifest_url=manifest_url, install_url=install_url)
    (directory / "build.json").write_text(json.dumps(metadata, indent=2) + "\n")
    mode = "<p>Enable Developer Mode on your iPhone for this development-signed build.</p>" if metadata["developer_mode"] else ""
    page = f'''<!doctype html><html lang="en"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex,nofollow"><title>Nostur test build</title>
<style>body{{font:17px system-ui;background:#111;color:#eee;max-width:440px;margin:50px auto;padding:24px}}
a{{display:block;padding:18px;border-radius:14px;background:#00a7ad;color:#fff;text-align:center;text-decoration:none}}
p{{line-height:1.5;color:#aaa}}code{{color:#eee}}</style>
<h1>Nostur test build</h1><p>Build <code>{html.escape(metadata['build_id'])}</code> · {html.escape(metadata['version'])}</p>
<a href="{html.escape(install_url, quote=True)}">Install latest build</a>
<p>Open this page in Safari on your registered iPhone. This replaces the installed Nostur app.</p>{mode}
<p>Provisioning expires {html.escape(metadata['expires'][:10])}.</p></html>'''
    # Publish IPA + manifest assets before replacing the stable landing page remotely.
    atomic_write(site / "index.html", page.encode())
    atomic_write(site / "latest.json", (json.dumps(metadata, indent=2) + "\n").encode())
    return metadata


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=ROOT / "scripts/ota-config.json")
    parser.add_argument("--archive", type=Path, help="Reuse an existing device archive (skip compiling)")
    parser.add_argument("--base-url", help="HTTPS install-site URL; omit to export an IPA only")
    parser.add_argument("--udid", help="Registered iPhone UDID; every exported profile must include it")
    parser.add_argument("--method", choices=["release-testing", "debugging"])
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    config = json.loads(args.config.read_text()) if args.config.exists() else {}
    udid = args.udid or config.get("device_udid")
    if not udid:
        parser.error("Provide --udid or device_udid in the local config.")
    base_url = args.base_url or config.get("base_url")
    if base_url:
        base_url = https_base(base_url)
    method = args.method or config.get("method", "release-testing")
    if method not in ["release-testing", "debugging"]:
        parser.error("Only registered-device export methods are supported.")
    output = (args.output or Path(config.get("output", ROOT / ".ota-builds"))).expanduser().resolve()
    output.mkdir(parents=True, exist_ok=True)
    with (output / ".build.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        work = output / "work"
        work.mkdir(exist_ok=True)
        archive = args.archive.resolve() if args.archive else work / "Nostur.xcarchive"
        if args.archive is None:
            if archive.exists():
                shutil.rmtree(archive)  # Only our explicitly owned work archive.
            now = dt.datetime.now(dt.timezone.utc)
            build_number = f"{(now.date() - dt.date(2020, 1, 1)).days}.{now.hour}.{now.minute}"
            run(["xcodebuild", "-scheme", "Nostur", "-configuration", "Debug",
                 "-destination", "generic/platform=iOS", "-archivePath", str(archive),
                 "-allowProvisioningUpdates", "CURRENT_PROJECT_VERSION=" + build_number, "archive"], work / "archive.log")
        if not (archive / "Info.plist").exists():
            raise ValueError("The device archive is missing or incomplete.")
        options = {"method": method, "destination": "export", "signingStyle": "automatic",
                   "teamID": config.get("team_id", "5T4GDWX88Z"),
                   "iCloudContainerEnvironment": "Production", "thinning": "<none>"}
        options_path = work / "ExportOptions.plist"
        options_path.write_bytes(plistlib.dumps(options))
        export = work / ("export-" + uuid.uuid4().hex)
        run(["xcodebuild", "-exportArchive", "-archivePath", str(archive), "-exportPath", str(export),
             "-exportOptionsPlist", str(options_path), "-allowProvisioningUpdates"], work / "export.log")
        packages = list(export.glob("*.ipa"))
        if len(packages) != 1:
            raise ValueError("Expected one exported IPA.")
        with tempfile.TemporaryDirectory(prefix="verify-", dir=work) as directory:
            run(["ditto", "-x", "-k", str(packages[0]), directory], work / "unpack.log")
            applications = list((Path(directory) / "Payload").glob("*.app"))
            if len(applications) != 1:
                raise ValueError("Expected one exported application.")
            run(["codesign", "--verify", "--deep", "--strict", str(applications[0])], work / "signature.log")
        metadata = inspect_ipa(packages[0], udid)
        latest = output / "Nostur.ipa"
        shutil.copy2(packages[0], latest.with_suffix(".ipa.tmp"))
        os.replace(latest.with_suffix(".ipa.tmp"), latest)
        atomic_write(output / "build.json", (json.dumps(metadata, indent=2) + "\n").encode())
        if base_url:
            stage_site(latest, metadata, base_url, output / "site")
            print(f"Install site staged at {output / 'site'}; upload assets first, index.html last.")
            print(f"Landing page: {base_url}/")
        else:
            print("IPA exported and device provisioning verified. Hosting URL pending; no install site generated.")
        print(f"Build {metadata['build_id']}: {latest}")
        shutil.rmtree(export)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
