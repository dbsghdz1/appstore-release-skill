---
name: appstore-release
description: macOS 앱을 fastlane으로 App Store에 배포한다 (아카이브→업로드→메타데이터→심사 제출). "앱스토어 배포", "심사 제출", "릴리즈해줘", 재제출·심사 취소 요청 시 사용. 실전에서 검증된 ASC 에러 플레이북 포함.
---

# App Store 배포 자동화 (macOS)

fastlane + App Store Connect API 도구로 아카이브부터 심사 제출까지 자동화한다. 실제 출시 과정에서 밟은 지뢰들의 해법(에러 플레이북)이 핵심이다.

## 0. 전제 조건 확인

1. 프로젝트에 `fastlane/Fastfile`이 있는가 — 없으면 이 스킬 저장소의 `examples/Fastfile`을 복사해 프로젝트에 맞게 수정 (release/upload/submit 3개 lane + metadata 폴더 구조).
2. `fastlane/.env`에 `ASC_KEY_ID`·`ASC_ISSUER_ID`, `fastlane/AuthKey.p8` 존재 확인 (`examples/env.example` 참고). ASC API 키는 팀 단위라 같은 계정의 다른 프로젝트 것을 재사용해도 된다 (**App Manager 권한** 필요 — Developer 권한은 업로드만 되고 메타데이터·제출이 안 된다).
3. `git status` 깨끗한지, 빌드 통과하는지 확인.

## 1. ASC API 도구 준비

이 스킬의 `scripts/asc.swift`가 fastlane이 못 하는 ASC 작업을 처리한다. 첫 사용 시 컴파일해 캐시:

```bash
cd <스킬폴더>/scripts && swiftc -O asc.swift -o asc
```

| 명령 | 역할 |
|---|---|
| `asc apps` | 팀 앱 목록 (appId 확인) |
| `asc state <appId>` | 버전 상태 + 연결된 빌드 + 로케일별 스크린샷 수 |
| `asc cancel-review <appId>` | WAITING_FOR_REVIEW 제출 자진 취소 |
| `asc app-infos <appId>` | appInfo id·로케일·이름·privacy URL 목록 |
| `asc add-locale <appInfoId> <locale> <이름> <서브타이틀>` | 이름을 지정해 로케일 선생성 |
| `asc set-privacy <appInfoId> <url>` | privacyPolicyUrl 빈 로케일 전부 채움 |

프로젝트 루트에서 실행하면 `fastlane/.env`를 자동으로 읽는다.

## 2. 버전 준비

- 코드 변경이 있으면 **빌드 넘버를 반드시 올린다**: `*.xcodeproj/project.pbxproj`의 `CURRENT_PROJECT_VERSION` (설정 2곳). 마케팅 버전(MARKETING_VERSION)은 사용자와 상의.
- What's New 갱신: `fastlane/metadata/*/release_notes.txt` — **모든 로케일** 동시에.
- 심사 중인 버전의 빌드를 바꿔야 하면: `asc cancel-review <appId>` → 수정 → 재제출. 텍스트 메타데이터만 고칠 땐 취소 불필요 (Waiting for Review 중에도 수정 가능).

## 3. 실행

```bash
fastlane mac release   # 아카이브 + 업로드 + 메타데이터 + 심사 제출 + 자동 출시
fastlane mac upload    # 빌드 업로드까지만
fastlane mac submit    # 업로드 없이 스크린샷 반영 + 제출만 (이미 올라간 빌드 사용)
```

- 오래 걸리므로 백그라운드로 실행하고 완료를 기다린다.
- 로그에서 `Successfully submitted the app for review!` 확인 → `asc state <appId>`로 WAITING_FOR_REVIEW 재확인.

## 4. 에러 플레이북 (전부 실전에서 밟아본 지뢰)

| 에러 | 원인 | 해법 |
|---|---|---|
| `Cannot add localization due to app name` | fastlane은 "로케일 생성→이름 적용" 순서라, 생성 시점에 기본 이름이 복사되는데 그 이름을 다른 앱이 선점 | `asc app-infos`로 편집 가능한(PREPARE) appInfo id 확인 → `asc add-locale`로 **차별화된 이름과 함께 선생성** 후 fastlane 재실행 |
| `is not in valid state - cannot be reviewed` | 제출 요건 미충족 — 대부분 새 로케일 스크린샷 0장 또는 빌드 미연결 | `asc state`로 로케일별 스크린샷 수 확인. `fastlane deliver download_screenshots`로 기존 승인본을 받아 `fastlane/screenshots/<locale>/`에 복사 → `fastlane mac submit` |
| `missing ... 'privacyPolicyUrl'` | 새로 만든 로케일의 개인정보 처리방침 URL이 비어 있음 | `asc set-privacy <appInfoId> <url>` (기존 로케일 값 재사용) |
| 구매 버튼 무반응 (상품 조회 실패) | ① 빌드가 요청하는 상품 ID ≠ ASC 상품 ID (`strings <바이너리> \| grep <상품ID>`로 빌드 내용 확인) ② 유료 앱 계약(Paid Apps Agreement) 미활성 ③ 승인 직후 전파 지연(최대 하루) ④ 메뉴바 전용(LSUIElement) 앱은 결제 시트를 붙일 창이 없음 | ①은 코드 재빌드보다 ASC에 맞는 ID로 상품 재생성이 빠름 ④는 구매 순간에만 투명 앵커 창을 key로 세우고, macOS 15.2+는 `purchase(confirmIn:)` 사용 |
| IAP 프로모션 이미지 업로드 거부 | 1024×1024여도 **알파 채널**이 있으면 거부 | `sips -s format jpeg`로 평탄화 (JPEG/알파 없는 PNG) |
| 첫 비소모성 IAP 단독 제출 불가 ("add an app version") | 첫 IAP는 앱 버전과 한 묶음으로만 심사 가능 | 버전 제출(리뷰 서브미션)에 IAP를 함께 담는다 |

## 5. 사후 처리

- `asc state <appId>`로 최종 상태를 확인해 사용자에게 보고.
- 치명 버그 수정 제출이면 expedited review 요청 안내: https://developer.apple.com/contact/app-store/?topic=expedite (개발자 본인이 웹폼 제출).
- 새 지뢰를 밟았으면 이 플레이북에 추가할 것.

## 참고: 기타 교훈

- 스크린샷 심사 기준(2.3.3): 홍보형 합성 이미지는 반려된다. **무가공 풀스크린 캡처**가 가장 안전. Media Manager의 모든 사이즈 슬롯을 청소할 것 (첫 업로드가 전 사이즈에 복사되어 남는다).
- Support URL(1.5): 문의 수단(이메일)이 겉으로 보이는 페이지여야 한다.
- 메뉴바 전용 앱은 심사 노트에 "Dock 아이콘·창이 없는 LSUIElement 앱"임을 선제 기입 (2.1 정보 요청 예방).
- 스크린샷 자동 캡처 시: `caffeinate -d -i -u`로 디스플레이 잠자기 방지, 작업 화면 노출 주의.
