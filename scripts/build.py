#!/usr/bin/env python3
"""Build and ad-hoc sign a universal BananaCursor app."""
import argparse
import json
import plistlib
import re
import subprocess
from pathlib import Path
from urllib.parse import urlparse
from release_support import bundle_digest, sha256

ROOT = Path(__file__).resolve().parent.parent


def run(*command, **kwargs):
    return subprocess.run(command, check=True, **kwargs)


def main():
    config = json.loads((ROOT / "release.json").read_text())
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", default=config["version"])
    parser.add_argument("--build", type=int, default=config["build"])
    parser.add_argument("--feed-url", default=config["feedURL"])
    parser.add_argument("--derived-data", type=Path, default=ROOT / "build/DerivedData")
    parser.add_argument("--output", type=Path, help="Copy the signed app to this .app path")
    args = parser.parse_args()
    if not re.fullmatch(r"\d+\.\d+\.\d+", args.version) or args.build <= 0:
        parser.error("Use a stable major.minor.patch version and a positive build number")
    feed = urlparse(args.feed_url)
    if feed.scheme != "https" or not feed.hostname or feed.username or feed.password:
        parser.error("The feed URL must use HTTPS")
    sdk = ROOT / "build/dependencies" / f"Sparkle-{config['sparkleVersion']}"
    run(str(ROOT / "scripts/fetch-sparkle.sh"))
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    dirty = subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True).splitlines()
    derived = args.derived_data.resolve()
    derived.mkdir(parents=True, exist_ok=True)
    log = derived / "build.log"
    with log.open("w") as output:
        result = subprocess.run([
            "xcodebuild", "-quiet", "-project", str(ROOT / "Mousecape/Mousecape.xcodeproj"),
            "-scheme", "BananaCursor", "-configuration", "Release", "-destination", "generic/platform=macOS",
            "-derivedDataPath", str(derived), "CODE_SIGNING_ALLOWED=NO", "ARCHS=arm64 x86_64",
            "ONLY_ACTIVE_ARCH=NO", f"MARKETING_VERSION={args.version}", f"CURRENT_PROJECT_VERSION={args.build}", "build",
        ], cwd=ROOT, stdout=output, stderr=subprocess.STDOUT)
    if result.returncode:
        print("\n".join(log.read_text().splitlines()[-200:]))
        raise SystemExit(result.returncode)
    app = derived / "Build/Products/Release/BananaCursor.app"
    resources = app / "Contents/Resources"
    frameworks = app / "Contents/Frameworks"
    frameworks.mkdir(exist_ok=True)
    run("ditto", str(sdk / "Sparkle.framework"), str(frameworks / "Sparkle.framework"))
    run("ditto", str(sdk / "LICENSE"), str(resources / "Sparkle-LICENSE"))
    run("xcrun", "swift", str(ROOT / "scripts/installer-background.swift"), str(resources / "installer-background.tiff"))
    info_path = app / "Contents/Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    assert info["CFBundleShortVersionString"] == args.version
    assert info["CFBundleVersion"] == str(args.build)
    assert info["SUPublicEDKey"] == config["publicKey"]
    info["SUFeedURL"] = args.feed_url
    info_path.write_bytes(plistlib.dumps(info))
    helper = app / "Contents/Library/LoginItems/com.dmmeteo.BananaCursor.helper.app"
    run("codesign", "--force", "--sign", "-", "--entitlements", str(ROOT / "Mousecape/mousecloakHelper/mousecloakHelper.entitlements"), str(helper))
    run("codesign", "--force", "--sign", "-", str(app / "Contents/MacOS/mousecloak"))
    run("codesign", "--force", "--sign", "-", "--entitlements", str(ROOT / "Mousecape/Mousecape/Mousecape.entitlements"), str(app))
    run("codesign", "--verify", "--deep", "--strict", str(app))
    if args.output:
        destination = args.output.resolve()
        if destination.suffix != ".app" or destination.exists():
            parser.error("--output must be a new .app path")
        destination.parent.mkdir(parents=True, exist_ok=True)
        run("ditto", str(app), str(destination))
        app = destination
    receipt = {
        "revision": revision, "dirty": dirty, "version": args.version, "build": args.build,
        "bundleID": info["CFBundleIdentifier"], "feedURL": args.feed_url, "publicKey": info["SUPublicEDKey"],
        "executableSHA256": sha256(app / "Contents/MacOS/BananaCursor"),
        "bundleSHA256": bundle_digest(app),
        "signing": "ad-hoc; not notarized", "app": str(app),
    }
    receipt_path = app.parent / (app.name + ".build.json")
    receipt_path.write_text(json.dumps(receipt, indent=2) + "\n")
    print(app)
    print(receipt_path)


if __name__ == "__main__":
    main()
