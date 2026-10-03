# Direct iPhone test builds

`scripts/build-ota.py` archives the current checkout, exports a signed registered-device
IPA, checks that the requested iPhone is included in every app/extension profile,
and optionally stages an HTTPS installation page. It never uploads to TestFlight,
a hosting service, or the phone. The main app retains its existing bundle ID,
keychain groups and Production CloudKit environment, and replaces installed Nostur.

Copy `scripts/ota-config.example.json` to the ignored `scripts/ota-config.json`.
Set your registered iPhone UDID. Leave `base_url` null until HTTPS hosting is ready.
Use `release-testing` for Ad Hoc distribution; Xcode automatic signing may need
access to your developer account to obtain distribution signing assets. `debugging`
is also supported with development signing; those builds require Developer Mode.

```sh
./scripts/build-ota.py
# Reuse a completed device archive without recompiling:
./scripts/build-ota.py --archive /path/to/Nostur.xcarchive
# Stage installation files once hosting is ready:
./scripts/build-ota.py --base-url https://your-host.example/nostur-tests
```

The default output is the ignored `.ota-builds/` directory. `Nostur.ipa` and
`build.json` identify the verified latest export. Build IDs come from the exported
Mach-O UUID, matching the app's sidebar. Export/compile diagnostics stay under
`work/`; provisioning contents and account credentials are never printed by the tool.

With a base URL configured, `site/` contains a stable `index.html` installation page
and unique `builds/<timestamp-id>/` IPA/manifest URLs to prevent stale cached installs.
Upload new build assets first, then `latest.json` and `index.html` last. Serve over
HTTPS, with `.plist` as XML and `.ipa` as `application/octet-stream`. The iPhone's
installer must be able to fetch the manifest and IPA directly; a web login whose
cookies are only available in Safari is insufficient. Use appropriately scoped
signed URLs or a private reachable distribution destination if access control is
needed. Do not publish the build unless that destination is explicitly selected.

Keep the latest few remote build folders after uploads are confirmed. Never prune
the folder referenced by `latest.json`, or a build still being installed. No automatic
remote deletion or uploading is implemented until a hosting destination is chosen.
Open the stable install page in Safari on the registered phone, then tap Install.
Installation over cellular and preservation of the existing app data need a real
phone smoke test after hosting is connected.

## Local setup prepared on 2026-10-02

The ignored local config has the known iPhone UDID and uses `debugging` export.
A signed archive and verified development IPA are saved under `.ota-builds/`.
Ad Hoc (`release-testing`) export was unavailable because the Xcode developer
account credentials and distribution certificate need setup. Cached development
profiles exported successfully and include the iPhone in all three bundles.
The main exported application passed `codesign --verify --deep --strict`.
The installation site has not been published; its HTTPS destination is pending.
