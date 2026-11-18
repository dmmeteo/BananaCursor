#!/usr/bin/env python3
"""Package a clean, signed build into a DMG, updater ZIP, and signed appcast."""
import argparse
import importlib.util
import json
import os
import plistlib
import subprocess
import tempfile
import zipfile
from importlib.metadata import version
from pathlib import Path
from xml.etree import ElementTree as ET
from release_support import bundle_digest, bundle_tree as tree, sha256

ROOT = Path(__file__).resolve().parent.parent
SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"


def run(*command, **kwargs):
    return subprocess.run(command, check=True, **kwargs)


def output(*command):
    return subprocess.check_output(command, text=True).strip()


def require(condition, message):
    if not condition:
        raise SystemExit(message)


def verify_app(app, config, receipt):
    require(bundle_digest(app) == receipt["bundleSHA256"], "App differs from build receipt")
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    for key, expected in {
        "CFBundleIdentifier": config["bundleID"], "CFBundleShortVersionString": config["version"],
        "CFBundleVersion": str(config["build"]), "SUPublicEDKey": config["publicKey"],
        "SUFeedURL": config["feedURL"], "SURequireSignedFeed": True,
        "SUVerifyUpdateBeforeExtraction": True, "SUSignedFeedFailureExpirationInterval": 0,
        "SUEnableAutomaticChecks": False, "SUAutomaticallyUpdate": False, "SUEnableSystemProfiling": False,
    }.items():
        require(info.get(key) == expected, f"Bundle {key} differs from release configuration")
    require(info["LSMinimumSystemVersion"] == config["minimumOS"], "Minimum OS differs")
    executable = app / "Contents/MacOS/BananaCursor"
    require(sha256(executable) == receipt["executableSHA256"], "Executable differs from build receipt")
    helper = app / "Contents/Library/LoginItems/com.dmmeteo.BananaCursor.helper.app"
    helper_info = plistlib.loads((helper / "Contents/Info.plist").read_bytes())
    require(helper_info["CFBundleIdentifier"] == "com.dmmeteo.BananaCursor.helper", "Helper identity differs")
    require(helper_info["CFBundleVersion"] == str(config["build"]), "Helper build differs")
    for binary in [executable, app / "Contents/MacOS/mousecloak", helper / "Contents/MacOS" / helper_info["CFBundleExecutable"]]:
        require(set(output("lipo", "-archs", str(binary)).split()) == {"arm64", "x86_64"}, f"Not universal: {binary}")
    require((app / "Contents/Resources/LICENSE").read_bytes() == (ROOT / "LICENSE").read_bytes(), "App license differs")
    sdk = ROOT / "build/dependencies" / f"Sparkle-{config['sparkleVersion']}"
    require((app / "Contents/Resources/Sparkle-LICENSE").read_bytes() == (sdk / "LICENSE").read_bytes(), "Sparkle license differs")
    run("codesign", "--verify", "--deep", "--strict", str(app))


def verify_feed(feed, archive, config, sdk):
    items = ET.parse(feed).findall("./channel/item")
    require(len(items) == 1, "Expected exactly one update in the initial feed")
    item = items[0]
    enclosure = item.find("enclosure")
    require(enclosure is not None, "Missing ZIP enclosure")
    require(item.findtext(SPARKLE + "version") == str(config["build"]), "Feed build differs")
    require(item.findtext(SPARKLE + "shortVersionString") == config["version"], "Feed version differs")
    require(item.findtext(SPARKLE + "minimumSystemVersion") == config["minimumOS"], "Feed minimum OS differs")
    prefix = f"https://github.com/dmmeteo/BananaCursor/releases/download/v{config['version']}/"
    require(enclosure.get("url") == prefix + archive.name, "Feed enclosure URL differs")
    require(int(enclosure.get("length", "0")) == archive.stat().st_size, "Feed ZIP length differs")
    signature = enclosure.get(SPARKLE + "edSignature")
    require(bool(signature), "ZIP signature is missing")
    run(str(sdk / "bin/sign_update"), "--account", config["keyAccount"], "--verify", str(archive), signature)
    run(str(sdk / "bin/sign_update"), "--account", config["keyAccount"], "--verify", str(feed))


def main():
    config = json.loads((ROOT / "release.json").read_text())
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, default=ROOT / "build/DerivedData/Build/Products/Release/BananaCursor.app")
    parser.add_argument("--output", type=Path, default=ROOT / "build/release" / config["version"])
    args = parser.parse_args()
    require(version("dmgbuild") == "1.6.7", "Use scripts/package-release.sh for pinned dmgbuild")
    require(not output("git", "-C", str(ROOT), "status", "--porcelain"), "Release packaging requires a clean worktree")
    revision = output("git", "-C", str(ROOT), "rev-parse", "HEAD")
    app = args.app.resolve()
    build_receipt = json.loads((app.parent / (app.name + ".build.json")).read_text())
    require(build_receipt["revision"] == revision and not build_receipt["dirty"], "Build receipt is dirty or from a different revision; rebuild")
    for key in ["version", "build", "bundleID", "feedURL", "publicKey"]:
        require(build_receipt[key] == config[key], f"Build receipt {key} differs from release configuration")
    require(config["build"] > config["previousBuild"], "Build must increase")
    require(tuple(map(int, config["version"].split("."))) > tuple(map(int, config["previousVersion"].split("."))), "Version must increase")
    sdk = ROOT / "build/dependencies" / f"Sparkle-{config['sparkleVersion']}"
    run(str(ROOT / "scripts/fetch-sparkle.sh"))
    require(output(str(sdk / "bin/generate_keys"), "--account", config["keyAccount"], "-p") == config["publicKey"], "Keychain public key differs; do not regenerate the release key")
    verify_app(app, config, build_receipt)
    expected_tree = tree(app)
    destination = args.output.resolve()
    require(not destination.exists(), "Output directory already exists; choose a new --output directory")
    destination.mkdir(parents=True)
    archive = destination / f"BananaCursor-{config['version']}-macos.zip"
    run("ditto", "--norsrc", "--noextattr", "-c", "-k", "--keepParent", str(app), str(archive))
    with zipfile.ZipFile(archive) as contents:
        require(all(name.startswith("BananaCursor.app/") and ".." not in Path(name).parts for name in contents.namelist()), "ZIP must contain exactly BananaCursor.app")
    with tempfile.TemporaryDirectory(prefix="bananacursor-package-") as temporary:
        temporary = Path(temporary)
        run("ditto", "-x", "-k", str(archive), str(temporary / "extracted"))
        extracted = temporary / "extracted/BananaCursor.app"
        require(tree(extracted) == expected_tree, "ZIP changes signed app contents")
        verify_app(extracted, config, build_receipt)
        stage = temporary / "feed"
        stage.mkdir()
        run("ditto", str(archive), str(stage / archive.name))
        prefix = f"https://github.com/dmmeteo/BananaCursor/releases/download/v{config['version']}/"
        run(str(sdk / "bin/generate_appcast"), "--account", config["keyAccount"], "--download-url-prefix", prefix, "--maximum-deltas", "0", str(stage))
        feed = destination / "appcast.xml"
        run("ditto", str(stage / "appcast.xml"), str(feed))
        verify_feed(feed, archive, config, sdk)
    spec = importlib.util.spec_from_file_location("package_dmg", ROOT / "scripts/package-dmg.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    dmg = destination / "BananaCursor.dmg"
    module.build_dmg(app, dmg)
    attached = plistlib.loads(subprocess.check_output(["hdiutil", "attach", "-readonly", "-nobrowse", "-plist", str(dmg)]))
    mount = Path(next(entity["mount-point"] for entity in attached["system-entities"] if "mount-point" in entity))
    try:
        require({p.name for p in mount.iterdir() if not p.name.startswith(".")} == {"BananaCursor.app", "Applications"}, "Unexpected visible DMG contents")
        require((mount / "Applications").is_symlink() and os.readlink(mount / "Applications") == "/Applications", "Applications link differs")
        require(tree(mount / "BananaCursor.app") == expected_tree, "DMG changes signed app contents")
        verify_app(mount / "BananaCursor.app", config, build_receipt)
    finally:
        run("hdiutil", "detach", str(mount))
    require(tree(app) == expected_tree, "Packaging changed the signed source app")
    artifacts = [dmg, archive, feed]
    sums = "".join(f"{sha256(path)}  {path.name}\n" for path in artifacts)
    (destination / "SHA256SUMS.txt").write_text(sums)
    receipt = {key: build_receipt[key] for key in ["revision", "version", "build", "bundleID", "feedURL", "publicKey", "executableSHA256", "bundleSHA256", "signing"]}
    receipt["artifacts"] = {path.name: {"sha256": sha256(path), "bytes": path.stat().st_size} for path in artifacts}
    receipt["verified"] = ["universal binaries", "strict signatures", "identical ZIP and DMG app", "signed feed and ZIP", "public key continuity"]
    receipt["nativeAcceptance"] = "Required before publication; packaging does not launch or install the app."
    (destination / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(destination)


if __name__ == "__main__":
    main()
