---
name: appstore-release
description: Release macOS/iOS apps to the App Store with fastlane (archive → upload → metadata → submit for review). Use for "release to the App Store", "submit for review", "ship it", resubmissions, or canceling a review. Includes a battle-tested App Store Connect error playbook.
---

# Automated App Store Release (macOS & iOS)

Automates everything from archive to review submission using fastlane plus an ASC API tool. The core value is the error playbook — every entry was hit in a real release.

## 0. Preflight

1. Does the project have `fastlane/Fastfile`? If not, copy `examples/Fastfile` from this skill's repository and adapt it — it contains both `platform :mac` and `platform :ios` blocks (release/upload/submit lanes, iOS also gets `beta` for TestFlight) plus the metadata folder layout.
2. Confirm `fastlane/.env` has `ASC_KEY_ID` / `ASC_ISSUER_ID` and `fastlane/AuthKey.p8` exists (see `examples/env.example`). ASC API keys are team-wide, so a key from another project on the same account works — it must have the **App Manager** role (Developer-role keys can upload but cannot edit metadata or submit).
3. Check `git status` is clean and the project builds.

## 1. ASC API tool

This skill's `scripts/asc.swift` handles what fastlane can't. Compile once and cache:

```bash
cd <skill-folder>/scripts && swiftc -O asc.swift -o asc
```

| Command | Purpose |
|---|---|
| `asc apps` | List team apps (find the appId) |
| `asc state <appId>` | Version states + attached build + screenshots per locale |
| `asc cancel-review <appId>` | Cancel a WAITING_FOR_REVIEW submission |
| `asc app-infos <appId>` | List appInfo ids, locales, names, privacy URLs |
| `asc add-locale <appInfoId> <locale> <name> <subtitle>` | Pre-create a locale with an explicit name |
| `asc set-privacy <appInfoId> <url>` | Fill privacyPolicyUrl on every locale missing it |
| `asc set-primary <appId> <locale>` | Change the app's primary locale |

Run from the project root and it auto-loads `fastlane/.env`.

## 2. Version prep

- If code changed, **always bump the build number**: `CURRENT_PROJECT_VERSION` in `*.xcodeproj/project.pbxproj` (two configurations). Discuss MARKETING_VERSION changes with the user.
- Update What's New: `fastlane/metadata/*/release_notes.txt` — **every locale** at once.
- To replace the build of a version already in review: `asc cancel-review <appId>` → fix → resubmit. Text metadata can be edited while Waiting for Review without canceling.

## 3. Run

```bash
# use `mac` or `ios` depending on the target platform
fastlane mac release   # archive + upload + metadata + submit + auto-release
fastlane mac upload    # build upload only
fastlane mac submit    # screenshots + submit only, using the already-uploaded build
fastlane ios beta      # iOS only: push a build to TestFlight
```

- These take a while — run in the background and wait for completion.
- Look for `Successfully submitted the app for review!` in the log, then re-verify with `asc state <appId>` (WAITING_FOR_REVIEW).

## 4. Error playbook (every one hit in production)

| Error | Cause | Fix |
|---|---|---|
| `Cannot add localization due to app name` | fastlane creates the locale first and applies your name second — at creation time the primary locale's name is copied, and another app owns it in that locale | `asc app-infos` to find the editable (PREPARE) appInfo id → `asc add-locale` to **pre-create with a differentiated name** → re-run fastlane |
| `is not in valid state - cannot be reviewed` | Submission requirements unmet — usually a new locale has zero screenshots, or no build attached | `asc state` shows screenshots per locale. `fastlane deliver download_screenshots` to fetch the approved set, copy into `fastlane/screenshots/<locale>/` → `fastlane mac submit` |
| `missing ... 'privacyPolicyUrl'` | Newly created locales have an empty privacy policy URL | `asc set-privacy <appInfoId> <url>` (reuse the existing locale's value) |
| Purchase button does nothing (product fetch fails) | ① Product ID in the binary ≠ ASC product ID (check with `strings <binary> \| grep <productID>`) ② Paid Apps Agreement not active ③ Post-approval propagation delay (up to a day) ④ Menu-bar-only (LSUIElement) apps have no window to anchor the StoreKit purchase sheet | For ① recreating the ASC product to match the binary is faster than a rebuild. For ④ create a transparent key window for the duration of the purchase, and use `purchase(confirmIn:)` on macOS 15.2+ |
| IAP promo image upload rejected | Even at 1024×1024, an **alpha channel** gets it rejected | Flatten with `sips -s format jpeg` (JPEG or alpha-free PNG) |
| First non-consumable IAP can't be submitted alone ("add an app version") | The first IAP must ride with an app version | Include the IAP in the version's review submission |

## 5. Post-submit

- Verify final state with `asc state <appId>` and report to the user.
- If this fixes a critical bug, point the user to expedited review: https://developer.apple.com/contact/app-store/?topic=expedite (they submit the web form themselves).
- If you hit a new mine, add it to this playbook.

## Appendix: other lessons

- Screenshot review (2.3.3): promotional composites get rejected. **Unedited full-screen captures** are safest. Clean every size slot in Media Manager (the first upload copies itself into all sizes).
- Support URL (1.5): the page must visibly show a contact method (email).
- Menu-bar-only apps: preempt the 2.1 information request by stating "LSUIElement app with no Dock icon or windows" in the review notes.
- When automating screenshot capture: prevent display sleep with `caffeinate -d -i -u`, and beware of capturing the user's actual work screen.
