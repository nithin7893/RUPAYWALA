# RUPAYWALA — C-02 Android Release INTERNET Permission Fix Report

**Date:** 23 November 2026
**Scope:** C-02 only (Android release `INTERNET` permission). C-01 email OTP security work is out of scope and untouched.
**Status:** FIXED and build-verified. Live release API connectivity was **not** tested.

---

## 1. Root cause

The project was generated from the standard Flutter Android template, which declares
`android.permission.INTERNET` only in the **debug** and **profile** source sets, with a comment
saying it is needed for the Flutter tool (hot reload, breakpoints).

| Source manifest | Original `INTERNET` declaration |
|---|---|
| `android/app/src/main/AndroidManifest.xml` | **absent** |
| `android/app/src/debug/AndroidManifest.xml:6` | present |
| `android/app/src/profile/AndroidManifest.xml:6` | present |
| `android/app/src/release/AndroidManifest.xml` | does not exist |

Android manifest merging therefore produced a release manifest that inherited **no** `INTERNET`
permission. A grep of all app/plugin manifests and Gradle build files found no dependency that
supplies it. The pre-fix merged release manifest contained only AndroidX's
`com.example.rupaywala_app.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` — confirming the audit finding
that a release APK could not reach the backend API.

This was not a dependency problem and not a manifest-merger ordering problem; the permission was
simply declared in the wrong source set for an app that needs network access at runtime.

---

## 2. Files modified

### C-02 fix (application source)

| File | Change |
|---|---|
| `rupaywala_mobile/android/app/src/main/AndroidManifest.xml` | Added `<uses-permission android:name="android.permission.INTERNET"/>` with an explanatory comment |
| `rupaywala_mobile/android/app/src/debug/AndroidManifest.xml` | Removed the now-redundant `INTERNET` declaration; it is inherited from `src/main` |
| `rupaywala_mobile/android/app/src/profile/AndroidManifest.xml` | Removed the now-redundant `INTERNET` declaration; it is inherited from `src/main` |

No permission was added to a `src/release` manifest because there is no release source set and
creating one would have been unnecessary: `src/main` applies to **all** variants. No application
attribute, activity, intent filter, `<queries>` entry, AndroidX permission, or security setting
was removed or altered.

### Android build-tool alignment (required to produce a buildable release APK)

The installed Flutter SDK is 3.50.1 / Dart 3.14.0, but the checked-in Android toolchain was
outdated; the first build failed with `Your project's Gradle version (8.12.0) is lower than
Flutter's minimum supported version of 9.3.1`. Versions were aligned to Flutter 3.50.1's own
template constants (`gradle_utils.dart`: Gradle 9.5.0, AGP 9.3.1, KGP 2.4.20):

| File | Change |
|---|---|
| `android/gradle/wrapper/gradle-wrapper.properties` | `gradle-8.12-all.zip` → `gradle-9.5.0-all.zip` (official `services.gradle.org` URL retained; no mirror URL committed) |
| `android/settings.gradle.kts` | AGP `8.9.1` → `9.3.1`; Kotlin Gradle plugin `2.1.0` → `2.4.20` |
| `android/app/build.gradle.kts` | Removed obsolete `kotlin-android` plugin; Java/Kotlin target `11` → `17`; added `kotlin { compilerOptions { jvmTarget = JVM_17 } }`; set `ndkVersion = "27.0.12077973"` (see blockers) |
| `android/gradle.properties` | Flutter tool automatically added `android.builtInKotlin=false` and `android.newDsl=false` |

No backend authentication, database schema, migration, Flutter screen, or `app_config.dart` code was
modified.

---

## 3. Manifest changes and verification

### Source declaration

`src/main/AndroidManifest.xml` now declares `INTERNET` once, before `<application>`, so it applies
to debug, profile, and release alike. Debug and profile source sets no longer declare it, so there
is a single source of truth and no duplicate source declarations.

### Baseline (before fix) — actual built release

- Built `flutter build apk --release --dart-define=API_BASE_URL=https://api.rupaywala.invalid`
  successfully: `app-release.apk`, 54,635,099 bytes.
- `build/app/intermediates/merged_manifests/release/processReleaseManifest/AndroidManifest.xml`
  contained **no** `android.permission.INTERNET`.
- Saved as `c02_baseline_merged_release_manifest.xml` for comparison.

### After fix

| Stage / artifact | `INTERNET` occurrences |
|---|---|
| `merged_manifest/release/processReleaseMainManifest/AndroidManifest.xml` | 1 |
| `merged_manifest/release/outputReleaseAppLinkSettings/AndroidManifest.xml` | 1 |
| `merged_manifests/release/processReleaseManifest/AndroidManifest.xml` | 1 |
| `packaged_manifests/release/.../AndroidManifest.xml` | 1 |
| APK binary (`aapt2 dump badging`) | 1 |

`aapt2 dump badging app-release.apk` reports exactly:

```
package: name='com.example.rupaywala_app' versionCode='1' versionName='1.0.0' ...
uses-permission: name='android.permission.INTERNET'
uses-permission: name='com.example.rupaywala_app.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION'
```

A line-by-line comparison of the baseline and fixed merged release manifests showed **only
additions** (the `INTERNET` declaration and its comment); nothing was removed. The AndroidX
`DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`, `<queries>` block, activity configuration, exported
flags, meta-data, and all plugin-injected components are unchanged.

Debug and profile builds both succeeded after the change, and their merged manifests each contain
`android.permission.INTERNET` (inherited from `src/main`) plus the AndroidX permission — confirming
the existing variants remain functional.

---

## 4. Release build results

All builds used `--dart-define=API_BASE_URL=https://api.rupaywala.invalid`, a non-localhost
placeholder, because no production URL exists in the repository.

| Variant | Result | Artifact |
|---|---|---|
| Release (baseline, pre-fix) | SUCCESS | 52.1 MB APK |
| Release (fixed) | SUCCESS | `build/app/outputs/flutter-apk/app-release.apk`, 52.1 MB, SHA1 `9791d4b6447ff8584da014498d1b39096963283e` |
| Debug | SUCCESS | `app-debug.apk` |
| Profile | SUCCESS | `app-profile.apk`, 71.5 MB |

Release build warnings (non-fatal): obsolete Java source/target 8 from a dependency, and an NDK
version mismatch (see blockers). The compiler emitted no errors and produced a valid APK.

---

## 5. API configuration findings

- `lib/core/config/app_config.dart` resolves `API_BASE_URL` from `String.fromEnvironment` first;
  only when no override is supplied does it fall back to `http://10.0.2.2:8000` (Android) or
  `http://127.0.0.1:8000` (other platforms).
- **There is no production API base URL defined anywhere in the repository**, and no runtime
  configuration mechanism beyond the compile-time `--dart-define`. The "intended production API
  configuration" therefore cannot be verified from this codebase. This is the separately tracked
  audit finding H-03 and remains open.
- The validation build embedded the placeholder `https://api.rupaywala.invalid` in the compiled
  release `libapp.so` (found once in the AOT string table). Because the override is checked first,
  the runtime base URL for this validation APK is the placeholder — not the emulator/loopback
  fallback.
- The legacy string `http://10.0.2.2:8000` is still present once in the AOT string table as a dead
  fallback constant from `app_config.dart`. This predates C-02 and was not introduced by the fix;
  it is not selected when an override is supplied. No localhost URL was added to release
  configuration, and no secret or production credential was embedded.

**Explicit separation:** permission presence in the merged manifest and APK was verified. This does
**not** validate live release API connectivity, DNS, TLS, or backend availability. No device/network
E2E test was performed.

---

## 6. Test results

| Check | Result |
|---|---|
| Android release build (fixed) | PASS — APK produced, `INTERNET` present in merged/packaged manifest and APK |
| Android debug build | PASS — `INTERNET` inherited from main manifest |
| Android profile build | PASS — `INTERNET` inherited from main manifest |
| `flutter analyze` | 0 errors, 0 warnings; 58 pre-existing **info**-level `deprecated_member_use` notices (`package:flutter/material.dart` deprecation in Flutter 3.50) |
| `flutter test` | **22 passed** |
| Backend full regression (`.\venv\Scripts\python.exe -m pytest --tb=no -ra`) | **428 passed, 0 failed** (197.03 s) |

The backend suite confirms no regressions from C-02 (or from the already-completed C-01). No tests
were skipped.

---

## 7. Remaining blockers / follow-ups

1. **Production API configuration (H-03) still open.** A production HTTPS base URL and a deployment
   mechanism must be supplied outside this change; the repository contains no such value. This C-02
   APK uses a non-localhost placeholder and is **not** a production-configured artifact.
2. **NDK version mismatch.** NDK `28.2.13676358` is the Flutter/plugin default but could not be
   installed — the download failed with insufficient disk space. The build was pinned to the already
   installed NDK `27.0.12077973`, which builds successfully but emits a warning because
   `flutter_secure_storage`, `path_provider_android`, and `url_launcher_android` declare 28.2.
   Install NDK 28.2.13676358 and restore `ndkVersion = flutter.ndkVersion` before final production
   signing.
3. **Release signing.** `app/build.gradle.kts` still uses the pre-existing TODO signing config (debug
   keys) for the release build type. Production signing was out of scope.
4. **Android licenses.** `flutter doctor -v` still reports "Some Android licenses not accepted."
   Local builds work, but this should be resolved on any clean build machine.
5. **Disk space.** Very low free space on `C:` repeatedly corrupted Gradle/Kotlin incremental caches
   and blocked an earlier NDK download. Caches were cleared and builds succeeded; this is an
   environment constraint, not a code defect.
6. **Live connectivity untested.** No deployment/E2E run was performed; only manifest, build, and
   compile-time configuration evidence is provided here.

---

## 8. Conclusion

The C-02 defect is corrected at the correct source-manifest layer. The actual release APK was built
and independently verified (merged manifest, packaged manifest, and `aapt2` APK inspection) to
contain `android.permission.INTERNET` exactly once, with all pre-existing permissions and security
configuration preserved. Debug and profile builds remain functional, Flutter tests pass (22), and
the full backend regression suite remains green at 428 passed. Work is stopped here pending approval.
