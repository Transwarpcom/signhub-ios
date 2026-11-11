import Foundation
import Security

/// 证书吊销检查（走系统 SecTrust 的 OCSP 策略）
enum RevocationChecker {

    enum Status {
        case valid           // 未被吊销
        case revoked         // 已吊销
        case unknown(String) // 查不到 / 网络失败
    }

    /// p12 里的叶子证书做一次链验证 + OCSP
    static func check(p12: URL, password: String, completion: @escaping (Status) -> Void) {
        guard let p12Data = try? Data(contentsOf: p12) else {
            completion(.unknown("读不到 p12 文件"))
            return
        }
        var items: CFArray?
        let opts = [kSecImportExportPassphrase as String: password] as CFDictionary
        let status = SecPKCS12Import(p12Data as CFData, opts, &items)
        guard status == errSecSuccess,
              let arr = items as? [[String: Any]],
              let first = arr.first,
              let identity = first[kSecImportItemIdentity as String] else {
            completion(.unknown("p12 解析失败（密码或格式）"))
            return
        }
        let id = identity as! SecIdentity
        var cert: SecCertificate?
        SecIdentityCopyCertificate(id, &cert)
        guard let cert else {
            completion(.unknown("取证书失败"))
            return
        }

        // 带上 WWDR 中间证书（系统钥匙串里有同名证书时 SecTrust 会自动补）
        let policy = SecPolicyCreateRevocation(kSecRevocationOCSPMethod | kSecRevocationRequirePositiveResponse)
        var trust: SecTrust?
        let ok = SecTrustCreateWithCertificates(cert, policy, &trust)
        guard ok == errSecSuccess, let trust else {
            completion(.unknown("创建 trust 失败"))
            return
        }

        var err: CFError?
        let valid = SecTrustEvaluateWithError(trust, &err)
        if valid {
            completion(.valid)
            return
        }
        let msg = (err as Error?)?.localizedDescription ?? "验证失败"
        // 区分「吊销」和「链不全」
        if msg.lowercased().contains("revok") {
            completion(.revoked)
        } else {
            completion(.unknown(shorten(msg)))
        }
    }

    /// 只做本地 DER 里的到期判断（不联网）
    static func localExpiry(_ date: Date?) -> String {
        guard let date else { return "未知" }
        let days = Int(date.timeIntervalSinceNow / 86400)
        if days > 0 { return "剩余 \(days) 天" }
        return "已过期 \(-days) 天"
    }

    private static func shorten(_ s: String) -> String {
        if s.count <= 60 { return s }
        return String(s.prefix(57)) + "…"
    }
}
