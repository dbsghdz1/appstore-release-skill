# appstore-release

**English** | [한국어](README.ko.md)

A [Claude Code](https://claude.com/claude-code) skill that automates macOS App Store releases — archive → upload → multi-language metadata → submit for review — with a battle-tested playbook for App Store Connect errors.

Built and verified while shipping a real Mac app ([Zappy](https://apps.apple.com/kr/app/zappy/id6794384033)) through three rejections, an IAP incident, and a five-language resubmission.

## What it does

Tell Claude Code "release my app to the App Store" and it will:

1. Manage build numbers, then run `fastlane mac release` (archive → sign → upload → push metadata for every locale → submit for review → auto-release)
2. Self-diagnose and fix the errors that actually block releases, using the **error playbook**:
   - `Cannot add localization due to app name` — pre-creates locales via the ASC API with a differentiated name when yours is taken
   - `not in valid state - cannot be reviewed` — detects locales with zero screenshots and backfills them
   - `missing privacyPolicyUrl` — patches new locales with your existing privacy URL
   - Silent StoreKit purchase failures in menu-bar (LSUIElement) apps, IAP images rejected for alpha channels, and more
3. Check review status and cancel submissions straight from the API with the bundled `asc` CLI

## Install

```bash
git clone https://github.com/dbsghdz1/appstore-release-skill.git
cp -r appstore-release-skill/appstore-release ~/.claude/skills/
```

Restart Claude Code and the skill loads. It triggers on requests like "release to the App Store", "submit for review", or "cancel the review".

## Requirements

- Xcode + distribution certificates (Apple Distribution, Mac Installer Distribution)
- [fastlane](https://fastlane.tools) (`brew install fastlane`)
- An App Store Connect API key with the **App Manager** role ([how to create one](https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api))
- A `fastlane/Fastfile` in your project — copy [`examples/Fastfile`](examples/Fastfile) and change the app name. See [`examples/env.example`](examples/env.example) for auth setup.

## Layout

```
appstore-release/
├── SKILL.md            # Release procedure + error playbook (the skill itself)
└── scripts/asc.swift   # ASC API CLI — zero dependencies (Swift + CryptoKit only)
examples/
├── Fastfile            # release / upload / submit lanes
└── env.example
```

`asc.swift` is a single file that compiles with plain `swiftc` — it signs its own ES256 JWTs, so there is nothing to install:

```bash
swiftc -O asc.swift -o asc
./asc apps                # list your team's apps
./asc state <appId>       # version states + attached build + screenshots per locale
./asc cancel-review <appId>
./asc add-locale <appInfoId> ja "MyApp: すごいアプリ" "subtitle"
./asc set-privacy <appInfoId> https://example.com/privacy
./asc set-primary <appId> en-US
```

## Why this exists

fastlane's deliver is great — until the first time you add localizations. Then the ASC submission errors cascade (name conflicts → screenshots → privacy URLs), and deliver can't dig itself out. This skill packages the full recovery path, learned the hard way, in a form Claude can reuse. Read the playbook in SKILL.md for the details.

## License

MIT © 2026 Hong Yun
