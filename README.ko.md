# appstore-release

[English](README.md) | **한국어**

macOS·iOS 앱의 App Store 배포를 처음부터 끝까지 자동화하는 [Claude Code](https://claude.com/claude-code) 스킬입니다: **아카이브 → 서명 → 업로드 → 다국어 메타데이터 → 스크린샷 → 심사 제출 → 자동 출시**. 그리고 더 중요한 것 — 자동 배포를 중간에 멈춰 세우는 App Store Connect 오류들을 스스로 복구합니다.

## 이게 뭔가요?

Claude Code 스킬은 Claude에게 반복 가능한 작업 절차를 가르치는 지침 패키지입니다. 이 스킬을 설치하면 *"앱스토어에 배포해줘"* 한마디에 Claude가 즉흥적으로 움직이는 대신 검증된 절차를 따릅니다: 설정을 점검하고, 빌드 넘버를 올리고, fastlane을 돌리고, 실패하면 로그를 읽어 **에러 플레이북**에서 맞는 해법을 찾아 실행하고, 마지막에 ASC API로 최종 상태를 검증합니다.

스킬은 두 부분으로 구성됩니다:

1. **SKILL.md** — Claude가 따르는 배포 절차. 에러 플레이북의 모든 항목은 문서에서 베낀 게 아니라 실제 출시에서 직접 밟고 해결한 지뢰들입니다.
2. **scripts/asc.swift** — fastlane이 못 미치는 구간을 메꾸는 의존성 0짜리 App Store Connect API CLI: 심사 자진 취소, 로케일 선생성, privacy URL 패치, 기본 언어 변경.

## Claude가 따르는 워크플로

**1. 사전 점검** — `fastlane/Fastfile` 존재 확인(없으면 `examples/Fastfile` 제안), ASC API 키 설정 확인(`fastlane/.env` + `AuthKey.p8`), git 상태와 빌드 통과 확인.

**2. 버전 준비** — 코드가 바뀌었으면 Xcode 프로젝트의 `CURRENT_PROJECT_VERSION`을 올리고, 마케팅 버전은 사용자에게 물어보고, `fastlane/metadata/`의 **모든 로케일** `release_notes.txt` 갱신을 챙깁니다 (일부만 갱신하면 제출이 실패해요).

**3. 배포 실행** — 세 가지 lane 중 하나를 백그라운드로 돌리며 로그를 감시:

| Lane | 하는 일 |
|---|---|
| `fastlane mac release` | 아카이브 → 서명 → 업로드 → 전 로케일 메타데이터 → 제출 → 자동 출시 |
| `fastlane mac upload` | 빌드 업로드만 (제출은 나중에 수동) |
| `fastlane mac submit` | 이미 올라간 빌드로 스크린샷 반영 + 제출만 |

**4. 오류 복구** — fastlane이 실패하면 포기하는 대신 플레이북과 대조해 해법을 실행:

| 오류 | 근본 원인 | 자동 해법 |
|---|---|---|
| `Cannot add localization due to app name` | fastlane은 로케일을 먼저 만들고 이름을 나중에 적용 — 생성 시점에 기본 로케일 이름이 복사되는데, 그 이름을 새 로케일에서 다른 앱이 선점한 경우 | `asc add-locale`로 **차별화된 이름과 함께** 로케일을 선생성한 뒤 fastlane 재실행 |
| `is not in valid state - cannot be reviewed` | 어떤 로케일의 스크린샷이 0장이거나 빌드 미연결 | `asc state`로 어느 로케일인지 특정 → `fastlane deliver download_screenshots`로 승인본을 받아 채움 |
| `missing 'privacyPolicyUrl'` | 새로 만든 로케일의 개인정보 URL이 비어 있음 — 제출 실패 전까지 UI에서 안 보임 | `asc set-privacy`가 기존 URL을 빈 로케일 전부에 복사 |
| 인앱 구매 버튼이 조용히 무반응 | 바이너리-ASC 상품 ID 불일치, 유료 앱 계약 미활성, 승인 직후 전파 지연, 또는 메뉴바 전용(LSUIElement) 앱이라 **StoreKit 결제 시트를 붙일 창이 없음** | 체크리스트 순서대로 진단 (`strings`로 바이너리 확인, 계약 상태, 그리고 투명 앵커 창 + macOS 15.2+ `purchase(confirmIn:)` 패턴) |
| IAP 프로모션 이미지 거부 | 1024×1024가 맞아도 **알파 채널**이 있으면 거부 | `sips`로 평탄화 |
| 첫 비소모성 IAP 단독 제출 불가 | 첫 IAP는 앱 버전과 한 묶음으로만 심사 가능 | 버전의 리뷰 서브미션에 함께 담기 |

**5. 사후 확인** — API로 `WAITING_FOR_REVIEW` 검증 후 보고. 치명 버그 수정이면 Apple 긴급 심사(expedited review) 신청 경로 안내.

## `asc` CLI

Swift 파일 하나, `swiftc`로 컴파일, ES256 JWT 서명도 직접 — Ruby gem도 npm도 파이썬 패키지도 필요 없습니다. 자격 증명은 환경변수 또는 `fastlane/.env`에서 자동으로 읽어요.

```bash
swiftc -O asc.swift -o asc

./asc apps                                        # 팀 앱 목록과 ID
./asc state <appId>                               # 버전·연결된 빌드·로케일별 스크린샷 수
./asc cancel-review <appId>                       # 제출 철회 (예: 빌드 교체할 때)
./asc app-infos <appId>                           # appInfo id + 로케일별 이름/privacy URL
./asc add-locale <appInfoId> ja "MyApp: 便利ツール" "서브타이틀"
./asc set-privacy <appInfoId> https://example.com/privacy
./asc set-primary <appId> en-US                   # 스토어 기본 언어 변경
```

일상적으로 제일 쓰는 건 `state`예요 — "왜 제출이 안 되지?"를 명령 하나로 답해줍니다 (어느 로케일에 스크린샷이 빠졌는지, 빌드가 붙긴 했는지).

## 설치

```bash
git clone https://github.com/dbsghdz1/appstore-release-skill.git
cp -r appstore-release-skill/appstore-release ~/.claude/skills/
```

Claude Code를 재시작하면 로드됩니다. "앱스토어 배포", "심사 제출", "재제출", "심사 취소" 같은 요청에 발동돼요.

## 준비물

1. **인증서**: Apple Distribution + Mac Installer Distribution (Xcode Organizer로 업로드해본 적 있다면 이미 있음)
2. **fastlane**: `brew install fastlane`
3. **ASC API 키**: App Store Connect → Users and Access → Integrations → App Store Connect API → **App Manager 권한** Team Key. (Developer 권한 키는 업로드만 되고 메타데이터·제출이 안 되는 게 흔한 함정.) `.p8`은 딱 한 번만 다운로드 가능.
4. **프로젝트 파일**: `examples/Fastfile`을 `fastlane/Fastfile`로 복사해 앱/스킴 이름 교체, `examples/env.example`을 `fastlane/.env`로 복사해 키 정보 입력. `AuthKey.p8`과 `.env`는 git에 올리지 말 것.
5. **메타데이터**: `fastlane/metadata/<locale>/`에 `name.txt`·`subtitle.txt`·`description.txt`·`keywords.txt`·`release_notes.txt`·`privacy_url.txt`·`support_url.txt` — 표준 [fastlane deliver](https://docs.fastlane.tools/actions/deliver/) 구조라 `fastlane deliver download_metadata`로 기존 등록정보에서 부트스트랩할 수 있어요.

## 구성

```
appstore-release/
├── SKILL.md            # Claude가 따르는 절차 + 에러 플레이북
└── scripts/asc.swift   # ASC API CLI (Swift + CryptoKit만)
examples/
├── Fastfile            # release / upload / submit lane
└── env.example         # ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH
```

## 범위와 참고

- **macOS와 iOS 둘 다 지원합니다**: `examples/Fastfile`에 `platform :mac`·`platform :ios` 블록이 함께 들어 있어요 (`fastlane mac release` / `fastlane ios release`). iOS에는 TestFlight용 `beta` lane도 추가. 에러 플레이북과 `asc` CLI는 플랫폼 무관 (StoreKit 결제 시트 항목만 맥 메뉴바 앱 한정).
- ASC API 키는 계정 전반의 권한을 가지니 `.p8`/`.env`를 반드시 gitignore하고, 필요 시 폐기할 수 있는 전용 키를 쓰세요.
- 이 도구는 자격 증명을 Apple API 외 어디에도 저장·전송하지 않습니다.

## License

MIT © 2026 Hong Yun
