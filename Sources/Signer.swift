import Foundation

/// 调 zsign 做重签名。全部在后台线程跑。
enum Signer {

    struct Result {
        let ok: Bool
        let log: String
        let outputURL: URL?
    }

    static func sign(ipa: URL,
                     p12: URL,
                     password: String,
                     profile: URL,
                     output: URL,
                     bundleId: String? = nil,
                     displayName: String? = nil,
                     version: String? = nil,
                     minOS: String? = nil,
                     removePlugins: Bool = false,
                     removeWatch: Bool = false,
                     dylibs: [URL] = [],
                     logHandler: ((String) -> Void)? = nil) -> Result {

        // 先解包到临时目录，做完修改再交给 zsign（这样 -E 之类不依赖 zsign 版本）
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("signwork-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: work) }

        var logs: [String] = []
        func log(_ s: String) { logs.append(s); logHandler?(s) }

        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let unzipDir = work.appendingPathComponent("unzip")
            try FileManager.default.createDirectory(at: unzipDir, withIntermediateDirectories: true)
            log("解包 \(ipa.lastPathComponent)")
            try unzip(ipa, to: unzipDir)

            let payload = unzipDir.appendingPathComponent("Payload")
            let apps = (try? FileManager.default.contentsOfDirectory(at: payload,
                                                                    includingPropertiesForKeys: nil))?
                .filter { $0.pathExtension == "app" } ?? []
            guard let app = apps.first else {
                log("包里没有 .app")
                return Result(ok: false, log: logs.joined(separator: "\n"), outputURL: nil)
            }
            log("App: \(app.lastPathComponent)")

            // 移除插件 / Watch
            if removePlugins {
                let plugins = app.appendingPathComponent("PlugIns")
                if FileManager.default.fileExists(atPath: plugins.path) {
                    try? FileManager.default.removeItem(at: plugins)
                    log("已移除 PlugIns")
                }
            }
            if removeWatch {
                for sub in ["Watch", "AppClips"] {
                    let p = app.appendingPathComponent(sub)
                    if FileManager.default.fileExists(atPath: p.path) {
                        try? FileManager.default.removeItem(at: p)
                        log("已移除 \(sub)")
                    }
                }
            }

            // 改 Info.plist
            let infoURL = app.appendingPathComponent("Info.plist")
            if var plist = NSDictionary(contentsOf: infoURL) as? [String: Any] {
                var changed = false
                if let displayName, !displayName.isEmpty {
                    plist["CFBundleDisplayName"] = displayName
                    plist["CFBundleName"] = displayName
                    changed = true
                }
                if let bundleId, !bundleId.isEmpty {
                    plist["CFBundleIdentifier"] = bundleId
                    changed = true
                }
                if let version, !version.isEmpty {
                    plist["CFBundleShortVersionString"] = version
                    changed = true
                }
                if let minOS, !minOS.isEmpty {
                    plist["MinimumOSVersion"] = minOS
                    changed = true
                }
                if changed {
                    (plist as NSDictionary).write(to: infoURL, atomically: true)
                    log("已改 Info.plist")
                }
            }

            // 注入动态库
            if !dylibs.isEmpty {
                let fw = app.appendingPathComponent("Frameworks")
                try? FileManager.default.createDirectory(at: fw, withIntermediateDirectories: true)
                for d in dylibs {
                    let dst = fw.appendingPathComponent(d.lastPathComponent)
                    try? FileManager.default.removeItem(at: dst)
                    try? FileManager.default.copyItem(at: d, to: dst)
                    log("注入 \(d.lastPathComponent)")
                }
            }

            // 重新打包成 ipa
            let repacked = work.appendingPathComponent("repacked.ipa")
            try zip(unzipDir, to: repacked)
            log("重新打包完成")

            // zsign 签名
            var args = ["zsign",
                        "-k", p12.path,
                        "-p", password,
                        "-m", profile.path,
                        "-o", output.path,
                        repacked.path]
            for d in dylibs {
                args += ["-l", d.path]
            }

            log("调用 zsign")
            var cArgs: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
            defer { cArgs.forEach { free($0) } }
            let code = cArgs.withUnsafeMutableBufferPointer { buf -> Int32 in
                zsign_run_main_c(Int32(buf.count), buf.baseAddress)
            }

            let ok = code == 0 && FileManager.default.fileExists(atPath: output.path)
            log("zsign exit=\(code) ok=\(ok)")
            return Result(ok: ok, log: logs.joined(separator: "\n"), outputURL: ok ? output : nil)

        } catch {
            log("失败: \(error.localizedDescription)")
            return Result(ok: false, log: logs.joined(separator: "\n"), outputURL: nil)
        }
    }

    // MARK: 解压 / 打包

    private static func unzip(_ src: URL, to dst: URL) throws {
        let data = try Data(contentsOf: src)
        let entries = try parseEntries(data)
        let fm = FileManager.default
        for e in entries {
            let out = dst.appendingPathComponent(e.name)
            if e.name.hasSuffix("/") {
                try? fm.createDirectory(at: out, withIntermediateDirectories: true)
                continue
            }
            try? fm.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
            let raw = data.subdata(in: e.dataStart..<e.dataEnd)
            let body: Data
            if e.method == 0 { body = raw }
            else if e.method == 8 { body = inflateRaw(raw, expected: e.uncompressedSize) ?? Data() }
            else { continue }
            try body.write(to: out)
        }
    }

    private static func zip(_ dir: URL, to out: URL) throws {
        // 简单做法：用 zip 命令行不可用，这里手工拼 store 模式
        var chunks: [Data] = []
        var central = Data()
        var offset = 0
        let fm = FileManager.default
        guard let en = fm.enumerator(at: dir, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        var files: [URL] = []
        for case let u as URL in en {
            let isDir = (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            files.append(u)
            if isDir { files.append(u.appendingPathComponent(".")) }
        }
        // 上一步只是收集，实际按文件写
        files = files.filter { u in
            var d: ObjCBool = false
            fm.fileExists(atPath: u.path, isDirectory: &d)
            return !d.boolValue
        }

        func dosTime(_ date: Date) -> (UInt16, UInt16) {
            let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            let hh: UInt16 = UInt16(c.hour ?? 0)
            let mm: UInt16 = UInt16(c.minute ?? 0)
            let ss: UInt16 = UInt16((c.second ?? 0) / 2)
            let t: UInt16 = (hh << 11) | (mm << 5) | ss
            let yy: UInt16 = UInt16((c.year ?? 2020) - 1980)
            let mo: UInt16 = UInt16(c.month ?? 1)
            let dd: UInt16 = UInt16(c.day ?? 1)
            let d: UInt16 = (yy << 9) | (mo << 5) | dd
            return (t, d)
        }

        for f in files.sorted(by: { $0.path < $1.path }) {
            let rel = f.path.replacingOccurrences(of: dir.path + "/", with: "")
            let nameData = Data(rel.utf8)
            let body = (try? Data(contentsOf: f)) ?? Data()
            let crc = crc32Of(body)
            let (t, d) = dosTime((try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date())

            var local = Data()
            local.append(u32(0x0403_4b50))
            local.append(u16(20))          // version
            local.append(u16(0))           // flags
            local.append(u16(0))           // method: store
            local.append(u16(t)); local.append(u16(d))
            local.append(u32(crc))
            local.append(u32(UInt32(body.count)))
            local.append(u32(UInt32(body.count)))
            local.append(u16(UInt16(nameData.count)))
            local.append(u16(0))
            local.append(nameData)
            local.append(body)

            var cen = Data()
            cen.append(u32(0x0201_4b50))
            cen.append(u16(20)); cen.append(u16(20))
            cen.append(u16(0)); cen.append(u16(0))
            cen.append(u16(t)); cen.append(u16(d))
            cen.append(u32(crc))
            cen.append(u32(UInt32(body.count)))
            cen.append(u32(UInt32(body.count)))
            cen.append(u16(UInt16(nameData.count)))
            cen.append(u16(0)); cen.append(u16(0))
            cen.append(u16(0)); cen.append(u16(0))
            cen.append(u32(0))
            cen.append(u32(UInt32(offset)))
            cen.append(nameData)
            central.append(cen)

            chunks.append(local)
            offset += local.count
        }

        var outData = Data()
        chunks.forEach { outData.append($0) }
        let centralOffset = outData.count
        outData.append(central)

        var eocd = Data()
        eocd.append(u32(0x0605_4b50))
        eocd.append(u16(0)); eocd.append(u16(0))
        eocd.append(u16(UInt16(files.count))); eocd.append(u16(UInt16(files.count)))
        eocd.append(u32(UInt32(central.count)))
        eocd.append(u32(UInt32(centralOffset)))
        eocd.append(u16(0))
        outData.append(eocd)

        try outData.write(to: out)
    }

    private static func u16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
    private static func u32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }

    // MARK: 条目解析（配合 Store 模式读出内容）

    struct RawEntry {
        let name: String
        let method: UInt16
        let uncompressedSize: Int
        let dataStart: Int
        let dataEnd: Int
    }

    private static func parseEntries(_ buf: Data) throws -> [RawEntry] {
        func u16(_ o: Int) -> UInt16 { UInt16(buf[o]) | (UInt16(buf[o+1]) << 8) }
        func u32(_ o: Int) -> UInt32 {
            UInt32(buf[o]) | (UInt32(buf[o+1]) << 8) | (UInt32(buf[o+2]) << 16) | (UInt32(buf[o+3]) << 24)
        }
        let n = buf.count
        var eocd = -1
        var i = n - 22
        while i >= max(0, n - 22 - 65535) {
            if u32(i) == 0x0605_4b50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw NSError(domain: "zip", code: 1) }
        let count = Int(u16(eocd + 10))
        var off = Int(u32(eocd + 16))
        var out: [RawEntry] = []
        for _ in 0..<count {
            guard off + 46 <= n, u32(off) == 0x0201_4b50 else { break }
            let method = u16(off + 10)
            let comp = Int(u32(off + 20))
            let uncomp = Int(u32(off + 24))
            let nameLen = Int(u16(off + 28))
            let extraLen = Int(u16(off + 30))
            let commentLen = Int(u16(off + 32))
            let lho = Int(u32(off + 42))
            guard off + 46 + nameLen <= n else { break }
            let name = String(data: buf.subdata(in: (off + 46)..<(off + 46 + nameLen)), encoding: .utf8) ?? ""
            // 定位本地头
            if lho + 30 <= n, u32(lho) == 0x0403_4b50 {
                let ln = Int(u16(lho + 26))
                let le = Int(u16(lho + 28))
                let start = lho + 30 + ln + le
                out.append(RawEntry(name: name, method: method, uncompressedSize: uncomp,
                                    dataStart: start, dataEnd: min(n, start + comp)))
            }
            off += 46 + nameLen + extraLen + commentLen
        }
        return out
    }

    private static func inflateRaw(_ data: Data, expected: Int) -> Data? {
        guard !data.isEmpty else { return Data() }
        var out = Data(count: max(expected, 1024))
        var outLen = uLongf(out.count)
        let r: Int32 = data.withUnsafeBytes { inPtr -> Int32 in
            guard let inBase = inPtr.bindMemory(to: Bytef.self).baseAddress else { return -1 }
            return out.withUnsafeMutableBytes { outPtr -> Int32 in
                guard let outBase = outPtr.bindMemory(to: Bytef.self).baseAddress else { return -1 }
                var strm = z_stream()
                strm.next_in = UnsafeMutablePointer(mutating: inBase)
                strm.avail_in = uInt(data.count)
                strm.next_out = outBase
                strm.avail_out = uInt(out.count)
                let ic = inflateInit2_(&strm, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
                guard ic == Z_OK else { return ic }
                defer { inflateEnd(&strm) }
                let code = inflate(&strm, Z_FINISH)
                outLen = uLongf(strm.total_out)
                return code
            }
        }
        guard r == Z_STREAM_END || r == Z_OK else { return nil }
        return out.prefix(Int(outLen))
    }

    private static func crc32Of(_ data: Data) -> UInt32 {
        var crc = uLong(0xffff_ffff)
        data.withUnsafeBytes { ptr in
            guard let base = ptr.bindMemory(to: Bytef.self).baseAddress else { return }
            crc = crc32(crc, base, uInt(data.count))
        }
        return UInt32(crc ^ 0xffff_ffff)
    }
}
