import platform
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
arch = platform.machine()
objects = ROOT / "build/DerivedData/Build/Intermediates.noindex/Mousecape.build/Release/Mousecape.build/Objects-normal" / arch
sdk = ROOT / "build/dependencies/Sparkle-2.10.1"
models = ROOT / "Mousecape/Mousecape/SwiftUI/Models"
engine = ["MCCursorLibrary", "MCLibraryController", "MCCursor", "MCPrefs", "MCDefs", "apply", "backup", "restore", "create", "scale", "NSBitmapImageRep+ColorSpace"]
headers = sorted({str(path.parent) for path in (ROOT / "Mousecape").rglob("*.h")})
binary = ROOT / "build/RegressionTests"
command = ["xcrun", "swiftc", "-swift-version", "6", "-parse-as-library", "-target", f"{arch}-apple-macos15.0",
           "-import-objc-header", str(ROOT / "Mousecape/Mousecape/Mousecape-Bridging-Header.h"),
           "-F", str(sdk), "-framework", "Sparkle", "-framework", "AppKit", "-framework", "ApplicationServices",
           "-framework", "Carbon", "-framework", "QuartzCore", "-framework", "UniformTypeIdentifiers",
           "-Xlinker", "-rpath", "-Xlinker", str(sdk), "-o", str(binary)]
for header in headers:
    command += ["-I", header]
command += [str(models / name) for name in ["AppState.swift", "AppUpdater.swift", "AppEnums.swift", "Cursor.swift", "CursorLibrary.swift"]]
command += [str(ROOT / "tests/RegressionTests.swift")] + [str(objects / f"{name}.o") for name in engine]
subprocess.run(command, check=True, cwd=ROOT)
subprocess.run([str(binary)], check=True, cwd=ROOT)
