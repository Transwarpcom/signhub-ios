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
                if m.build > currentBuild {
                    completion(.available(m))
                } else {
                    completion(.upToDate)
                }
            }
        }.resume()
    }

    static func install(_ m: Manifest) {
        let encoded = m.manifestURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? m.manifestURL
        guard let u = URL(string: "itms-services://?action=download-manifest&url=\(encoded)") else { return }
        UIApplication.shared.open(u, options: [:], completionHandler: nil)
    }
}
