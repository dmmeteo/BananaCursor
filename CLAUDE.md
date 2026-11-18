# BananaCursor

Read README.md for build and usage instructions. Build with `./scripts/build.sh`.

The SwiftUI app is under `Mousecape/Mousecape/SwiftUI`. Objective-C models and cursor application code remain shared with the bundled `mousecloak` CLI and login helper.

Runtime identity constants live in `Mousecape/mousecloak/MCPrefs.h` and `MCPrefs.m`. Keep the GUI, CLI, helper, build products, and `.cape` paths consistent when changing them. Preserve the upstream `.cape` format and Apple cursor identifiers.

The interface is English only. Keep user-facing text and documentation concise. Preserve LICENSE and source copyright notices.

Some Objective-C files use manual memory management. Check each file's compiler flags in `project.pbxproj` before changing ownership.

A build does not prove cursor application or helper registration. Verify those in the native app before claiming them. Do not register or unregister another installed cursor manager's helper.
