import Foundation
import UIKit

/// 包内自更新：查服务器上的 version.json，发现新版就触发 OTA 覆盖安装。
/// 限制：新包必须已经用同一张证书签好（App 内无法重签自己再替换自己）。
enum UpdateChecker {

    struct Manifest: Decodable {
        let version: String
        let build: Int
        let manifestURL: String
        let notes: String?
    }

    /// 服务器上的更新清单地址
    static let feedURL = "https://html.medwarp.cn/ipa/signhub-version.json"

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
    static var currentBuild: Int {
        Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0") ?? 0
    }

    enum CheckResult {
        case upToDate
        case available(Manifest)
        case failed(String)
    }

    static func check(completion: @escaping (CheckResult) -> Void) {
        guard let url = URL(string: feedURL) else { completion(.failed("地址无效")); return }
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 15
        URLSession.shared.dataTask(with: req) { data, _, err in
            DispatchQueue.main.async {
                if let err {
                    completion(.failed(err.localizedDescription)); return
                }
                guard let data,
                      let m = try? JSONDecoder().decode(Manifest.self, from: data)
                else {
                    completion(.failed("解析失败")); return
                }
                // 同时比较版本号和 build：任一更大就算有新版本
                let newer = compareVersion(m.version, currentVersion) > 0 || m.build > currentBuild
                if newer { completion(.available(m)) } else { completion(.upToDate) }
            }
        }.resume()
    }

    /// 1.7.0 vs 1.6.0 → 1；相等 → 0；更小 → -1
    static func compareVersion(_ a: String, _ b: String) -> Int {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y ? 1 : -1 }
        }
        return 0
    }

    static func install(_ m: Manifest) {
        let encoded = m.manifestURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? m.manifestURL
        guard let u = URL(string: "itms-services://?action=download-manifest&url=\(encoded)") else { return }
        UIApplication.shared.open(u, options: [:], completionHandler: nil)
    }
}
