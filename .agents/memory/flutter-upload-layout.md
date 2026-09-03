---
name: Flutter upload layout
description: Nonstandard uploaded Flutter Android trees and the platform files Flutter actually consumes.
---

When repairing an uploaded Flutter app, verify that Android manifests and
resources are under `android/app/src/main/`; a top-level `app/src/main/` tree
can look plausible but is ignored by Flutter's Android build.

**Why:** An uploaded prototype placed its manifest in a sibling `app/` folder,
which caused Flutter to report a legacy Android embedding error even though a
new `MainActivity` had been added.

**How to apply:** Inspect the Flutter-standard `android/` tree before changing
Dart code, then run `flutter analyze` and `flutter test` before attempting the
APK build.