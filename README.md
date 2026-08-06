# appstore-release

**Claude Code skill for automating macOS App Store releases** — archive → upload → metadata (multi-language) → submit for review, with a battle-tested playbook for App Store Connect errors.

macOS 앱의 App Store 배포를 자동화하는 [Claude Code](https://claude.com/claude-code) 스킬입니다. fastlane 파이프라인에, fastlane이 처리하지 못하는 구간을 메꾸는 **ASC API 도구**와 **실전 에러 플레이북**을 얹었습니다. 실제 맥앱([Zappy](https://apps.apple.com/kr/app/zappy/id6794384033))을 1.0 반려 3회부터 다국어 재제출까지 겪으며 검증했습니다.

## 뭘 해주나요

Claude Code에서 "앱스토어에 배포해줘" 한마디로:

1. 빌드 넘버 관리 → `fastlane mac release` (아카이브 → 서명 → 업로드 → 5개 언어든 몇 개든 메타데이터 반영 → 심사 제출 → 자동 출시)
2. 막히면 **에러 플레이북**으로 자가 진단·해결:
   - `Cannot add localization due to app name` — 앱 이름 선점 시 ASC API로 차별화 이름과 함께 로케일 선생성
   - `not in valid state - cannot be reviewed` — 로케일별 스크린샷 누락 탐지·복사
   - `missing privacyPolicyUrl` — 기존 로케일 값 일괄 패치
   - 메뉴바(LSUIElement) 앱의 StoreKit 결제 시트 무반응, IAP 이미지 알파 채널 거부 등
3. `asc` CLI로 심사 상태 확인·자진 취소까지 API로 처리

## 설치

```bash
git clone https://github.com/dbsghdz1/appstore-release-skill.git
cp -r appstore-release-skill/appstore-release ~/.claude/skills/
```

Claude Code를 재시작하면 스킬이 로드됩니다. 이후 "앱스토어 배포", "심사 제출", "릴리즈해줘" 같은 요청에 자동으로 발동돼요.

## 요구 사항

- Xcode + 배포 인증서 (Apple Distribution, Mac Installer Distribution)
- [fastlane](https://fastlane.tools) (`brew install fastlane`)
- App Store Connect API 키 — **App Manager 권한** ([발급 방법](https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api))
- 프로젝트에 `fastlane/Fastfile` — 없으면 [`examples/Fastfile`](examples/Fastfile)을 복사해 앱 이름만 바꾸면 됩니다. 인증 설정은 [`examples/env.example`](examples/env.example) 참고.

## 구성

```
appstore-release/
├── SKILL.md            # 배포 절차 + 에러 플레이북 (스킬 본체)
└── scripts/asc.swift   # ASC API CLI — 의존성 0 (Swift + CryptoKit만)
examples/
├── Fastfile            # release / upload / submit 3개 lane
└── env.example
```

`asc.swift`는 swiftc 하나로 컴파일되는 단일 파일입니다. ES256 JWT 서명부터 직접 하므로 별도 패키지 설치가 없어요:

```bash
swiftc -O asc.swift -o asc
./asc apps                # 팀 앱 목록
./asc state <appId>       # 버전 상태 + 빌드 + 로케일별 스크린샷 수
./asc cancel-review <appId>
./asc add-locale <appInfoId> ja "MyApp: すごいアプリ" "サブタイトル"
./asc set-privacy <appInfoId> https://example.com/privacy
```

## 왜 만들었나

fastlane deliver는 훌륭하지만, 다국어를 처음 추가하는 순간 연쇄적으로 터지는 ASC 제출 오류들(이름 선점 → 스크린샷 → privacy URL)은 스스로 해결하지 못합니다. 이 스킬은 그 실패 경로 전체를 한 번 완주하며 얻은 해법을 Claude가 재사용할 수 있는 형태로 담은 것입니다. 자세한 배경은 SKILL.md의 플레이북을 읽어보세요.

## License

MIT © 2026 Hong Yun
