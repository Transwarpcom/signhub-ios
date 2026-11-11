import Foundation
import SwiftUI
import Security

// MARK: - 数据模型

struct CertRecord: Codable, Identifiable, Equatable {
    // 容错解码：新增字段时老 JSON 缺 key 不会让整条记录消失
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        label = (try? c.decode(String.self, forKey: .label)) ?? ""
        password = (try? c.decode(String.self, forKey: .password)) ?? ""
        teamId = (try? c.decode(String.self, forKey: .teamId)) ?? ""
        subjectCN = (try? c.decode(String.self, forKey: .subjectCN)) ?? ""
        appId = (try? c.decode(String.self, forKey: .appId)) ?? ""
        expireAt = try? c.decodeIfPresent(Date.self, forKey: .expireAt)
        profileExpireAt = try? c.decodeIfPresent(Date.self, forKey: .profileExpireAt)
        deviceCount = (try? c.decode(Int.self, forKey: .deviceCount)) ?? 0
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date()
        p12Name = (try? c.decode(String.self, forKey: .p12Name)) ?? "cert.p12"
        profileName = (try? c.decode(String.self, forKey: .profileName)) ?? "profile.mobileprovision"
        uuid = (try? c.decode(String.self, forKey: .uuid)) ?? ""
        entitlements = (try? c.decode([EntitlementItem].self, forKey: .entitlements)) ?? []
    }

    init(id: String, label: String, password: String, teamId: String, subjectCN: String,
         appId: String, expireAt: Date?, profileExpireAt: Date?, deviceCount: Int,
         createdAt: Date, p12Name: String, profileName: String,
         uuid: String = "", entitlements: [EntitlementItem] = []) {
        self.id = id; self.label = label; self.password = password
        self.teamId = teamId; self.subjectCN = subjectCN; self.appId = appId
        self.expireAt = expireAt; self.profileExpireAt = profileExpireAt
        self.deviceCount = deviceCount; self.createdAt = createdAt
        self.p12Name = p12Name; self.profileName = profileName
        self.uuid = uuid; self.entitlements = entitlements
    }

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
    var uuid: String = ""
    var entitlements: [EntitlementItem] = []
}

struct EntitlementItem: Codable, Identifiable, Equatable, Hashable {
    var id: String { key }
    var key: String
    var value: String
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
    var iconPath: String = ""
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

    /// 只有一张证书且还没设过当前证书时，自动选中它
    func ensureCurrentCert() {
        let key = "hub.currentCert"
        let cur = UserDefaults.standard.string(forKey: key)
        if (cur == nil || cur?.isEmpty == true), let first = certs.first {
            UserDefaults.standard.set(first.id, forKey: key)
        }
        // 记录的证书已经被删了，指向第一张
        if let cur, !certs.contains(where: { $0.id == cur }), let first = certs.first {
            UserDefaults.standard.set(first.id, forKey: key)
        }
    }

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
            profileName: "profile.mobileprovision",
            uuid: info.uuid,
            entitlements: info.entitlements
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
        var uuid = ""
        var entitlements: [EntitlementItem] = []
    }

    nonisolated static func parseProfile(_ url: URL) -> ProfileInfo {
        var info = ProfileInfo()
        guard let raw = try? Data(contentsOf: url) else { return info }

        // mobileprovision = CMS 包裹的 XML plist。不用「第一个 <」定位，
        // 直接从字节里搜 "<?xml" 到 "</plist>"，避免命中 DER 里的 0x3C。
        let all = [UInt8](raw)
        guard let xmlStart = findBytes(all, Array("<?xml".utf8), from: 0),
              let plistEnd = findBytes(all, Array("</plist>".utf8), from: xmlStart)
        else { return info }

        let xmlData = Data(all[xmlStart..<(plistEnd + 8)])
        guard let d = try? PropertyListSerialization.propertyList(from: xmlData, format: nil) as? [String: Any]
        else { return info }

        info.teamId = (d["TeamIdentifier"] as? [String])?.first ?? ""
        info.profileExpireAt = d["ExpirationDate"] as? Date
        info.deviceCount = (d["ProvisionedDevices"] as? [String])?.count ?? 0
        info.uuid = d["UUID"] as? String ?? ""
        if let c = d["CreationDate"] as? Date { _ = c }
        if let ent = d["Entitlements"] as? [String: Any] {
            info.appId = ent["application-identifier"] as? String ?? ""
            info.subjectCN = ent["com.apple.developer.team-identifier"] as? String ?? ""
            info.entitlements = ent.keys.sorted().map { k in
                EntitlementItem(key: k, value: AppStore.describeValue(ent[k]))
            }
        }
        if let certs = d["DeveloperCertificates"] as? [Data], let first = certs.first {
            let (cn, exp) = parseCertCN(first)
            if !cn.isEmpty { info.subjectCN = cn }
            info.expireAt = exp
        }
        if info.expireAt == nil { info.expireAt = info.profileExpireAt }
        return info
    }

    /// 在字节数组里找子序列
    nonisolated static func findBytes(_ hay: [UInt8], _ needle: [UInt8], from: Int) -> Int? {
        guard !needle.isEmpty, hay.count >= needle.count else { return nil }
        var i = max(0, from)
        let limit = hay.count - needle.count
        while i <= limit {
            if hay[i] == needle[0] {
                var ok = true
                for j in 1..<needle.count where hay[i + j] != needle[j] { ok = false; break }
                if ok { return i }
            }
            i += 1
        }
        return nil
    }


    nonisolated static func describeValue(_ v: Any?) -> String {
        guard let v else { return "—" }
        if let b = v as? Bool { return b ? "是" : "否" }
        if let s = v as? String { return s }
        if let a = v as? [Any] {
            if a.isEmpty { return "[]" }
            return a.map { "\($0)" }.joined(separator: ", ")
        }
        return "\(v)"
    }

    /// 用 Security.framework 解析 DER 证书的 CN 和 notAfter
    nonisolated static func parseCertCN(_ der: Data) -> (String, Date?) {
        guard let cert = SecCertificateCreateWithData(nil, der as CFData) else { return ("", nil) }
        let cn = (SecCertificateCopySubjectSummary(cert) as String?) ?? ""
        return (cn, AppStore.notAfterFromDER(der))
    }

    /// 从 DER 里扫 UTCTime(0x17) / GeneralizedTime(0x18)，取最后一个（notAfter）
    nonisolated static func notAfterFromDER(_ der: Data) -> Date? {
        let b = [UInt8](der)
        var found: [String] = []
        var i = 0
        while i < b.count - 2 {
            if b[i] == 0x17 || b[i] == 0x18 {
                let len = Int(b[i + 1])
                if len >= 12, len <= 15, i + 2 + len <= b.count {
                    let slice = b[(i + 2)..<(i + 2 + len)]
                    if let str = String(bytes: slice, encoding: .ascii), str.hasSuffix("Z") {
                        found.append(str)
                    }
                }
            }
            i += 1
        }
        guard let last = found.last else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        if last.count == 13 {
            f.dateFormat = "yyMMddHHmmss'Z'"
        } else {
            f.dateFormat = "yyyyMMddHHmmss'Z'"
        }
        return f.date(from: last)
    }
}
