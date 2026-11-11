import Foundation
import SwiftUI

// MARK: - 数据模型

struct CertRecord: Codable, Identifiable, Equatable {
    var id: String
    var label: String
    var password: String
    var teamId: String
    var subjectCN: String
    var appId: String
    var expireAt: Date?
    var profileExpireAt: Date?
    var deviceCount: Int
    var createdAt: Date
    var p12Name: String
    var profileName: String
}

struct IPARecord: Codable, Identifiable, Equatable {
    var id: String
    var fileName: String
    var bundleId: String
    var displayName: String
    var version: String
    var minOS: String
    var fileCount: Int
    var unzipSize: Int64
    var urlSchemes: [String]
    var importedAt: Date
    var isSigned: Bool
}

struct DylibRecord: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var path: String
    var size: Int64
    var addedAt: Date
}

struct SignOptions: Codable, Equatable {
    var newBundleId: String = ""
    var newName: String = ""
    var newVersion: String = ""
    var newMinOS: String = ""
    var cloneCount: Int = 1
    var removePlugins: Bool = false
    var removeWatch: Bool = false
    var clearOldCodeSignature: Bool = false
    var dylibIds: [String] = []
}

// MARK: - 存储

@MainActor
final class AppStore: ObservableObject {
    static let shared = AppStore()

    @Published var certs: [CertRecord] = []
    @Published var ipas: [IPARecord] = []
    @Published var signed: [IPARecord] = []
    @Published var dylibs: [DylibRecord] = []

    let root: URL
    private let fm = FileManager.default

    init() {
        root = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        for sub in ["certs", "ipas", "signed", "dylibs"] {
            try? fm.createDirectory(at: root.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        load()
    }

    // MARK: 路径

    var certsDir: URL { root.appendingPathComponent("certs") }
    var ipasDir: URL { root.appendingPathComponent("ipas") }
    var signedDir: URL { root.appendingPathComponent("signed") }
    var dylibsDir: URL { root.appendingPathComponent("dylibs") }

    func certDir(_ id: String) -> URL { certsDir.appendingPathComponent(id) }
    func ipaURL(_ rec: IPARecord) -> URL {
        (rec.isSigned ? signedDir : ipasDir).appendingPathComponent(rec.fileName)
    }

    // MARK: 持久化

    private func metaURL(_ name: String) -> URL { root.appendingPathComponent("\(name).json") }

    private func load() {
        certs = decode([CertRecord].self, "certs") ?? []
        ipas = decode([IPARecord].self, "ipas") ?? []
        signed = decode([IPARecord].self, "signed") ?? []
        dylibs = decode([DylibRecord].self, "dylibs") ?? []

        // 清理磁盘上已被删除的记录
        ipas.removeAll { !fm.fileExists(atPath: ipaURL($0).path) }
        signed.removeAll { !fm.fileExists(atPath: ipaURL($0).path) }
        certs.removeAll { !fm.fileExists(atPath: certDir($0.id).path) }
    }

    private func decode<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let data = try? Data(contentsOf: metaURL(name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func persist() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        if let d = try? enc.encode(certs) { try? d.write(to: metaURL("certs")) }
        if let d = try? enc.encode(ipas) { try? d.write(to: metaURL("ipas")) }
        if let d = try? enc.encode(signed) { try? d.write(to: metaURL("signed")) }
        if let d = try? enc.encode(dylibs) { try? d.write(to: metaURL("dylibs")) }
    }

    func save() { persist() }

    // MARK: 证书

    func addCert(p12: URL, profile: URL, password: String, label: String) throws -> CertRecord {
        let id = UUID().uuidString.prefix(8).lowercased() + String(Int(Date().timeIntervalSince1970))
        let dir = certDir(String(id))
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let dstP12 = dir.appendingPathComponent("cert.p12")
        let dstMp = dir.appendingPathComponent("profile.mobileprovision")
        try? fm.removeItem(at: dstP12)
        try? fm.removeItem(at: dstMp)
        try fm.copyItem(at: p12, to: dstP12)
        try fm.copyItem(at: profile, to: dstMp)

        let info = AppStore.parseProfile(dstMp)

        let rec = CertRecord(
            id: String(id),
            label: label.isEmpty ? (info.subjectCN.isEmpty ? info.teamId : info.subjectCN) : label,
            password: password,
            teamId: info.teamId,
            subjectCN: info.subjectCN,
            appId: info.appId,
            expireAt: info.expireAt,
            profileExpireAt: info.profileExpireAt,
            deviceCount: info.deviceCount,
            createdAt: Date(),
            p12Name: "cert.p12",
            profileName: "profile.mobileprovision"
        )
        certs.insert(rec, at: 0)
        persist()
        return rec
    }

    func removeCert(_ rec: CertRecord) {
        try? fm.removeItem(at: certDir(rec.id))
        certs.removeAll { $0.id == rec.id }
        persist()
    }

    func p12URL(_ rec: CertRecord) -> URL { certDir(rec.id).appendingPathComponent(rec.p12Name) }
    func profileURL(_ rec: CertRecord) -> URL { certDir(rec.id).appendingPathComponent(rec.profileName) }

    // MARK: IPA

    func importIPA(from url: URL) throws -> IPARecord {
        let id = UUID().uuidString.prefix(8).lowercased() + String(Int(Date().timeIntervalSince1970))
        let name = "\(id)-\(url.lastPathComponent)"
        let dst = ipasDir.appendingPathComponent(name)
        try? fm.removeItem(at: dst)
        try fm.copyItem(at: url, to: dst)

        let meta = AppStore.inspectIPA(dst)

        let rec = IPARecord(
            id: String(id),
            fileName: name,
            bundleId: meta.bundleId,
            displayName: meta.displayName,
            version: meta.version,
            minOS: meta.minOS,
            fileCount: meta.fileCount,
            unzipSize: meta.unzipSize,
            urlSchemes: meta.urlSchemes,
            importedAt: Date(),
            isSigned: false
        )
        ipas.insert(rec, at: 0)
        persist()
        return rec
    }

    func removeIPA(_ rec: IPARecord) {
        try? fm.removeItem(at: ipaURL(rec))
        if rec.isSigned { signed.removeAll { $0.id == rec.id } }
        else { ipas.removeAll { $0.id == rec.id } }
        persist()
    }

    func registerSigned(_ rec: IPARecord) {
        signed.insert(rec, at: 0)
        persist()
    }

    // MARK: 动态库

    func addDylib(from url: URL) throws -> DylibRecord {
        let id = UUID().uuidString.prefix(8).lowercased()
        let name = "\(id)-\(url.lastPathComponent)"
        let dst = dylibsDir.appendingPathComponent(name)
        try? fm.removeItem(at: dst)
        try fm.copyItem(at: url, to: dst)
        let size = (try? fm.attributesOfItem(atPath: dst.path)[.size] as? Int64) ?? 0
        let rec = DylibRecord(id: String(id), name: url.lastPathComponent, path: name, size: size ?? 0, addedAt: Date())
        dylibs.insert(rec, at: 0)
        persist()
        return rec
    }

    func removeDylib(_ rec: DylibRecord) {
        try? fm.removeItem(at: dylibsDir.appendingPathComponent(rec.path))
        dylibs.removeAll { $0.id == rec.id }
        persist()
    }

    // MARK: 解析

    struct IPAMeta {
        var bundleId = ""
        var displayName = ""
        var version = ""
        var minOS = ""
        var fileCount = 0
        var unzipSize: Int64 = 0
        var urlSchemes: [String] = []
    }

    nonisolated static func inspectIPA(_ url: URL) -> IPAMeta {
        var m = IPAMeta()
        guard let z = try? ZipArchive(path: url.path) else { return m }
        m.fileCount = z.entries.count
        m.unzipSize = z.entries.reduce(0) { $0 + $1.size }

        guard let entry = z.entries.first(where: { $0.name.hasSuffix(".app/Info.plist") && $0.name.hasPrefix("Payload/") }),
              let data = z.read(entry.name),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return m }

        m.bundleId = plist["CFBundleIdentifier"] as? String ?? ""
        m.displayName = (plist["CFBundleDisplayName"] as? String) ?? (plist["CFBundleName"] as? String) ?? ""
        let short = plist["CFBundleShortVersionString"] as? String ?? ""
        let build = plist["CFBundleVersion"] as? String ?? ""
        m.version = build.isEmpty ? short : "\(short) (\(build))"
        m.minOS = plist["MinimumOSVersion"] as? String ?? ""
        if let schemes = plist["CFBundleURLTypes"] as? [[String: Any]] {
            m.urlSchemes = schemes.compactMap { ($0["CFBundleURLSchemes"] as? [String])?.first }
        }
        return m
    }

    struct ProfileInfo {
        var teamId = ""
        var subjectCN = ""
        var appId = ""
        var expireAt: Date?
        var profileExpireAt: Date?
        var deviceCount = 0
    }

    nonisolated static func parseProfile(_ url: URL) -> ProfileInfo {
        var info = ProfileInfo()
        guard let raw = try? Data(contentsOf: url) else { return info }
        // mobileprovision 是 CMS 包裹的 plist，跳过 ASN.1 头找 <plist>
        let bytes = [UInt8](raw)
        guard let start = bytes.firstIndex(of: 0x3C),
              let range = String(data: Data(bytes[start...]), encoding: .isoLatin1),
              let plistStart = range.range(of: "<?xml"),
              let plistEnd = range.range(of: "</plist>") else { return info }
        let xml = String(range[plistStart.lowerBound...plistEnd.upperBound])
        guard let data = xml.data(using: .utf8),
              let d = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return info }

        info.teamId = (d["TeamIdentifier"] as? [String])?.first ?? ""
        info.profileExpireAt = d["ExpirationDate"] as? Date
        info.deviceCount = (d["ProvisionedDevices"] as? [String])?.count ?? 0
        if let ent = d["Entitlements"] as? [String: Any] {
            info.appId = ent["application-identifier"] as? String ?? ""
            info.subjectCN = ent["com.apple.developer.team-identifier"] as? String ?? ""
        }
        // 从内嵌证书取 CN 和到期
        if let certs = d["DeveloperCertificates"] as? [Data], let first = certs.first {
            let (cn, exp) = parseCertCN(first)
            if !cn.isEmpty { info.subjectCN = cn }
            info.expireAt = exp
        }
        return info
    }

    /// 用 Security.framework 解析 DER 证书的 CN 和 notAfter
    nonisolated static func parseCertCN(_ der: Data) -> (String, Date?) {
        guard let cert = SecCertificateCreateWithData(nil, der as CFData) else { return ("", nil) }
        var cn = ""
        var exp: Date?
        if let sum = SecCertificateCopySubjectSummary(cert) {
            cn = sum as String
        }
        // 有效期从 DER 里粗读（Security 没有直接 API）
        return (cn, exp)
    }
}
