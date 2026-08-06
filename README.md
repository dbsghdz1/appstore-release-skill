# appstore-release

**English** | [한국어](README.ko.md)

A [Claude Code](https://claude.com/claude-code) skill that automates macOS App Store releases end-to-end: **archive → sign → upload → multi-language metadata → screenshots → submit for review → auto-release** — and, more importantly, recovers from the App Store Connect errors that usually stop an automated release halfway.

## What is this?

Claude Code skills are instruction packages that teach Claude a repeatable workflow. Install this one and a request like *"release my app to the App Store"* makes Claude follow a proven release procedure instead of improvising: it checks your setup, bumps build numbers, runs fastlane, reads the failure output when something breaks, applies the matching fix from the error playbook, and verifies the final state through the App Store Connect API.

The skill has two parts:

1. **SKILL.md** — the release procedure Claude follows, including an error playbook where every entry is a failure actually encountered (and solved) in a real release, not copied from docs.
2. **scripts/asc.swift** — a zero-dependency App Store Connect API CLI that covers the gaps fastlane can't reach: canceling review submissions, pre-creating localizations, patching privacy URLs, changing the primary locale.

## The workflow Claude follows

**1. Preflight** — verifies `fastlane/Fastfile` exists (offers `examples/Fastfile` if not), checks the ASC API key is configured (`fastlane/.env` + `AuthKey.p8`), confirms the working tree is clean and the project builds.

**2. Version prep** — bumps `CURRENT_PROJECT_VERSION` in the Xcode project when code changed, asks before touching the marketing version, and reminds you that `release_notes.txt` must be updated for **every** locale in `fastlane/metadata/` (a partial update fails submission).

**3. Release** — runs one of three lanes in the background and watches the log:

| Lane | What it does |
|---|---|
| `fastlane mac release` | archive → sign → upload → metadata for all locales → submit → auto-release |
| `fastlane mac upload` | build upload only (submit manually later) |
| `fastlane mac submit` | screenshots + submission only, reusing an already-uploaded build |

**4. Error recovery** — when fastlane fails, Claude matches the error against the playbook and executes the fix instead of giving up:

| Error | Root cause | Automated fix |
|---|---|---|
| `Cannot add localization due to app name` | fastlane creates a locale first and applies your localized name second — at creation time the primary locale's name is copied, and another app already owns that name in the new locale | Pre-create the localization **with a differentiated name** via `asc add-locale`, then re-run fastlane |
| `is not in valid state - cannot be reviewed` | A locale has zero screenshots, or no build is attached | `asc state` pinpoints which locale; download the approved screenshots with `fastlane deliver download_screenshots` and backfill |
| `missing 'privacyPolicyUrl'` | Freshly created locales have an empty privacy policy URL — invisible in the UI until submission fails | `asc set-privacy` copies your existing URL to every locale missing one |
| In-app purchase button silently does nothing | Product ID mismatch between binary and ASC, inactive Paid Apps Agreement, post-approval propagation delay, or — for menu-bar-only (LSUIElement) apps — **no window for StoreKit to anchor its purchase sheet on** | Playbook walks through each check (`strings` on the binary, agreement status, and the transparent-anchor-window pattern with `purchase(confirmIn:)` on macOS 15.2+) |
| IAP promo image rejected | The image has an alpha channel (even at a correct 1024×1024) | Flatten with `sips` |
| First non-consumable IAP "cannot be submitted" | The first IAP must ride along with an app version | Bundle it into the version's review submission |

**5. Post-submit** — verifies `WAITING_FOR_REVIEW` via the API, reports back, and points you to Apple's expedited-review form when the release fixes a critical bug.

## The `asc` CLI

Single Swift file, compiles with `swiftc`, signs its own ES256 JWTs — no Ruby gems, no npm, no python packages. Reads credentials from env vars or `fastlane/.env` automatically.

```bash
swiftc -O asc.swift -o asc

./asc apps                                        # list team apps and their IDs
./asc state <appId>                               # versions, attached build, screenshots per locale
./asc cancel-review <appId>                       # withdraw a submission (e.g. to swap the build)
./asc app-infos <appId>                           # appInfo ids + per-locale name / privacy URL
./asc add-locale <appInfoId> ja "MyApp: 便利ツール" "subtitle"
./asc set-privacy <appInfoId> https://example.com/privacy
./asc set-primary <appId> en-US                   # change the store's default language
```

`state` is the everyday one — it answers "why can't I submit?" in one command by showing exactly which locale is missing screenshots or whether the build ever attached.

## Install

```bash
git clone https://github.com/dbsghdz1/appstore-release-skill.git
cp -r appstore-release-skill/appstore-release ~/.claude/skills/
```

Restart Claude Code. The skill triggers on requests like "release to the App Store", "submit for review", "resubmit", or "cancel the review".

## Setup

1. **Certificates**: Apple Distribution + Mac Installer Distribution in your keychain (if you've ever uploaded via Xcode Organizer, you have them).
2. **fastlane**: `brew install fastlane`.
3. **ASC API key**: App Store Connect → Users and Access → Integrations → App Store Connect API → Team Key with the **App Manager** role. (Developer-role keys can upload builds but cannot edit metadata or submit — a common trap.) Download the `.p8` — it's downloadable exactly once.
4. **Project files**: copy `examples/Fastfile` to `fastlane/Fastfile` and replace the app/scheme names; copy `examples/env.example` to `fastlane/.env` and fill in the key ID / issuer ID. Keep `AuthKey.p8` and `.env` out of git.
5. **Metadata**: `fastlane/metadata/<locale>/` folders with `name.txt`, `subtitle.txt`, `description.txt`, `keywords.txt`, `release_notes.txt`, `privacy_url.txt`, `support_url.txt` per locale — this is standard [fastlane deliver](https://docs.fastlane.tools/actions/deliver/) layout, so `fastlane deliver download_metadata` can bootstrap it from an existing listing.

## Layout

```
appstore-release/
├── SKILL.md            # the procedure + error playbook Claude follows
└── scripts/asc.swift   # ASC API CLI (Swift + CryptoKit only)
examples/
├── Fastfile            # release / upload / submit lanes, ready to adapt
└── env.example         # ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH
```

## Scope & notes

- Lanes are written for **macOS apps** (`build_mac_app`, `platform: "osx"`). The structure adapts to iOS by switching to `build_app` and `platform: "ios"`; the error playbook and `asc` CLI are platform-agnostic.
- The ASC API key grants broad account access — keep `.p8`/`.env` gitignored (the example `.gitignore` entries are in `env.example`'s comments) and prefer a dedicated key you can revoke.
- Nothing here stores or transmits your credentials anywhere except directly to Apple's API.

## License

MIT © 2026 Hong Yun
