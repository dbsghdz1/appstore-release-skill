import Foundation
import CryptoKit

// App Store Connect API 도구 — appstore-release 스킬 동반 스크립트
// 인증: 환경변수 ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH,
//       없으면 현재 디렉토리의 fastlane/.env에서 자동 로드
//
// 컴파일: swiftc -O asc.swift -o asc   (스킬이 첫 사용 시 컴파일해 캐시)
//
// 사용법:
//   asc apps                                     팀 앱 목록 (이름·bundleId·appId)
//   asc state <appId>                            버전 상태 + 빌드 + 로케일별 스크린샷 수
//   asc cancel-review <appId>                    WAITING_FOR_REVIEW 제출 취소
//   asc app-infos <appId>                        appInfo 목록 + 로케일·이름 (편집 가능한 것 확인용)
//   asc add-locale <appInfoId> <locale> <이름> <서브타이틀>   이름을 지정해 로케일 선생성
//   asc set-privacy <appInfoId> <url>            privacyPolicyUrl 비어있는 로케일 전부 채움

func loadEnv() -> [String: String] {
    var env = ProcessInfo.processInfo.environment
    if env["ASC_KEY_ID"] == nil || env["ASC_ISSUER_ID"] == nil {
        for candidate in ["fastlane/.env", ".env"] {
            if let text = try? String(contentsOfFile: candidate, encoding: .utf8) {
                for line in text.split(separator: "\n") {
                    let parts = line.split(separator: "=", maxSplits: 1)
                    if parts.count == 2, env[String(parts[0])] == nil {
                        env[String(parts[0])] = String(parts[1])
                    }
                }
            }
        }
    }
    return env
}

let env = loadEnv()
guard let keyID = env["ASC_KEY_ID"], let issuerID = env["ASC_ISSUER_ID"] else {
    print("❌ ASC_KEY_ID / ASC_ISSUER_ID 필요 (환경변수 또는 fastlane/.env)"); exit(1)
}
let keyPath = env["ASC_KEY_PATH"] ?? "fastlane/AuthKey.p8"

func jwt() -> String {
    guard let pem = try? String(contentsOfFile: keyPath, encoding: .utf8),
          let key = try? P256.Signing.PrivateKey(pemRepresentation: pem) else {
        print("❌ 키 파일을 읽을 수 없음: \(keyPath)"); exit(1)
    }
    func b(_ d: Data) -> String {
        d.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    let now = Int(Date().timeIntervalSince1970)
    let h = try! JSONSerialization.data(withJSONObject: ["alg": "ES256", "kid": keyID, "typ": "JWT"])
    let p = try! JSONSerialization.data(withJSONObject: ["iss": issuerID, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"])
    let input = b(h) + "." + b(p)
    return input + "." + b(try! key.signature(for: Data(input.utf8)).rawRepresentation)
}

func call(_ method: String, _ path: String, _ body: [String: Any]? = nil) -> (Int, [String: Any]) {
    var req = URLRequest(url: URL(string: "https://api.appstoreconnect.apple.com\(path)")!)
    req.httpMethod = method
    req.setValue("Bearer \(jwt())", forHTTPHeaderField: "Authorization")
    if let body {
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try! JSONSerialization.data(withJSONObject: body)
    }
    var status = 0; var json: [String: Any] = [:]
    let sem = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: req) { d, r, _ in
        status = (r as? HTTPURLResponse)?.statusCode ?? 0
        if let d, let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { json = j }
        sem.signal()
    }.resume()
    sem.wait()
    return (status, json)
}

func errDetail(_ json: [String: Any]) -> String {
    ((json["errors"] as? [[String: Any]])?.first?["detail"] as? String) ?? "\(json)"
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("사용법: asc apps | state <appId> | cancel-review <appId> | app-infos <appId> | add-locale <appInfoId> <locale> <이름> <서브타이틀> | set-privacy <appInfoId> <url>")
    exit(1)
}

switch args[1] {
case "apps":
    let (_, j) = call("GET", "/v1/apps?fields[apps]=bundleId,name&limit=50")
    for app in (j["data"] as? [[String: Any]] ?? []) {
        let a = app["attributes"] as? [String: Any]
        print("- \(a?["name"] ?? "?") | \(a?["bundleId"] ?? "?") | appId: \(app["id"] ?? "?")")
    }

case "state":
    let appID = args[2]
    let (_, vers) = call("GET", "/v1/apps/\(appID)/appStoreVersions?limit=5")
    for v in (vers["data"] as? [[String: Any]] ?? []) {
        let a = v["attributes"] as? [String: Any]
        let id = v["id"] as? String ?? ""
        print("버전 \(a?["versionString"] ?? "?") | \(a?["appStoreState"] ?? "?") | id: \(id)")
        if (a?["appStoreState"] as? String) == "PREPARE_FOR_SUBMISSION" || (a?["appStoreState"] as? String) == "WAITING_FOR_REVIEW" {
            let (_, build) = call("GET", "/v1/appStoreVersions/\(id)/build")
            if let d = build["data"] as? [String: Any], let ba = d["attributes"] as? [String: Any] {
                print("  빌드: \(ba["version"] ?? "?") (\(ba["processingState"] ?? "?"))")
            } else { print("  빌드: ❌ 미연결") }
            for loc in (call("GET", "/v1/appStoreVersions/\(id)/appStoreVersionLocalizations?limit=15").1["data"] as? [[String: Any]] ?? []) {
                let lid = loc["id"] as? String ?? ""
                let locale = (loc["attributes"] as? [String: Any])?["locale"] as? String ?? "?"
                var shots = 0
                for s in (call("GET", "/v1/appStoreVersionLocalizations/\(lid)/appScreenshotSets?limit=5").1["data"] as? [[String: Any]] ?? []) {
                    shots += (call("GET", "/v1/appScreenshotSets/\(s["id"] as? String ?? "")/appScreenshots?limit=20").1["data"] as? [[String: Any]])?.count ?? 0
                }
                print("  \(locale): 스크린샷 \(shots)장")
            }
        }
    }

case "cancel-review":
    let appID = args[2]
    let (_, subs) = call("GET", "/v1/apps/\(appID)/reviewSubmissions?filter[state]=WAITING_FOR_REVIEW&limit=5")
    let list = subs["data"] as? [[String: Any]] ?? []
    if list.isEmpty { print("취소할 제출 없음") }
    for sub in list {
        let id = sub["id"] as? String ?? ""
        let (st, resp) = call("PATCH", "/v1/reviewSubmissions/\(id)",
            ["data": ["type": "reviewSubmissions", "id": id, "attributes": ["canceled": true]]])
        print(st == 200 ? "✅ 취소: \(id)" : "❌ [\(st)] \(errDetail(resp))")
    }

case "app-infos":
    let appID = args[2]
    for info in (call("GET", "/v1/apps/\(appID)/appInfos?limit=5").1["data"] as? [[String: Any]] ?? []) {
        let id = info["id"] as? String ?? "?"
        let state = (info["attributes"] as? [String: Any])?["appStoreState"] ?? (info["attributes"] as? [String: Any])?["state"] ?? "?"
        print("appInfo \(id) | \(state)")
        for loc in (call("GET", "/v1/appInfos/\(id)/appInfoLocalizations?limit=15").1["data"] as? [[String: Any]] ?? []) {
            let la = loc["attributes"] as? [String: Any]
            print("  \(la?["locale"] ?? "?") | \(la?["name"] ?? "?") | privacy: \(la?["privacyPolicyUrl"] ?? "없음") | id: \(loc["id"] ?? "?")")
        }
    }

case "add-locale":
    guard args.count >= 6 else { print("사용법: asc add-locale <appInfoId> <locale> <이름> <서브타이틀>"); exit(1) }
    let (st, resp) = call("POST", "/v1/appInfoLocalizations", ["data": [
        "type": "appInfoLocalizations",
        "attributes": ["locale": args[3], "name": args[4], "subtitle": args[5]],
        "relationships": ["appInfo": ["data": ["type": "appInfos", "id": args[2]]]]
    ]])
    print(st == 201 ? "✅ \(args[3]): \(args[4])" : "❌ [\(st)] \(errDetail(resp))")

case "set-privacy":
    guard args.count >= 4 else { print("사용법: asc set-privacy <appInfoId> <url>"); exit(1) }
    for loc in (call("GET", "/v1/appInfos/\(args[2])/appInfoLocalizations?limit=15").1["data"] as? [[String: Any]] ?? []) {
        let la = loc["attributes"] as? [String: Any]
        let locale = la?["locale"] as? String ?? "?"
        let id = loc["id"] as? String ?? ""
        if let existing = la?["privacyPolicyUrl"] as? String, !existing.isEmpty {
            print("· \(locale): 이미 있음"); continue
        }
        let (st, resp) = call("PATCH", "/v1/appInfoLocalizations/\(id)",
            ["data": ["type": "appInfoLocalizations", "id": id, "attributes": ["privacyPolicyUrl": args[3]]]])
        print(st == 200 ? "✅ \(locale)" : "❌ \(locale) [\(st)] \(errDetail(resp))")
    }

default:
    print("알 수 없는 명령: \(args[1])")
    exit(1)
}
