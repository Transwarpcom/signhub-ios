import Foundation

/// 调用 zsign 做重签名。全部在后台线程跑，进度通过回调返回。
final class Signer {

    struct Result {
        let ok: Bool
        let log: String
        let outputURL: URL?
    }

    /// - Parameters:
    ///   - ipa: 待签名的 IPA
    ///   - p12: 证书
    ///   - password: p12 密码
    ///   - profile: mobileprovision
    ///   - output: 输出路径
    ///   - bundleId / displayName / version: 可选覆盖
    static func sign(ipa: URL,
                     p12: URL,
                     password: String,
                     profile: URL,
                     output: URL,
                     bundleId: String? = nil,
                     displayName: String? = nil,
                     version: String? = nil,
                     logHandler: ((String) -> Void)? = nil) -> Result {

        var args: [String] = [
            "zsign",
            "-k", p12.path,
            "-p", password,
            "-m", profile.path,
            "-o", output.path
        ]
        if let bundleId, !bundleId.isEmpty { args += ["-b", bundleId] }
        if let displayName, !displayName.isEmpty { args += ["-n", displayName] }
        if let version, !version.isEmpty { args += ["-v", version] }
        args.append(ipa.path)

        logHandler?("$ zsign " + args.dropFirst().joined(separator: " "))

        // 转成 C 数组
        var cArgs: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
        defer { cArgs.forEach { free($0) } }

        let code = cArgs.withUnsafeMutableBufferPointer { buf -> Int32 in
            zsign_run_main(Int32(buf.count), buf.baseAddress)
        }

        let exists = FileManager.default.fileExists(atPath: output.path)
        let size = (try? FileManager.default.attributesOfItem(atPath: output.path)[.size] as? Int64) ?? 0
        let log = "exit=\(code) outputExists=\(exists) size=\(size ?? 0)"
        logHandler?(log)

        return Result(ok: code == 0 && exists, log: log, outputURL: exists ? output : nil)
    }
}
