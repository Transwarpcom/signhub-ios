import Foundation

/// 极简只读 ZIP 解析：够用来读 Info.plist、列出条目、算解压大小。
/// 支持 stored(0) 和 deflate(8) 两种压缩方式。
final class ZipArchive {
    struct Entry {
        let name: String
        let compressedSize: Int
        let uncompressedSize: Int
        let method: UInt16
        let localHeaderOffset: Int
        var size: Int64 { Int64(uncompressedSize) }
    }

    private let handle: FileHandle
    private let fileSize: Int
    private(set) var entries: [Entry] = []
    private var buf: Data

    init(path: String) throws {
        guard let h = FileHandle(forReadingAtPath: path) else {
            throw NSError(domain: "zip", code: 1, userInfo: [NSLocalizedDescriptionKey: "打不开文件"])
        }
        handle = h
        buf = h.readDataToEndOfFile()
        fileSize = buf.count
        try parse()
    }

    deinit { try? handle.close() }

    // MARK: 解析

    private func u16(_ o: Int) -> UInt16 {
        guard o + 2 <= buf.count else { return 0 }
        return UInt16(buf[o]) | (UInt16(buf[o + 1]) << 8)
    }
    private func u32(_ o: Int) -> UInt32 {
        guard o + 4 <= buf.count else { return 0 }
        return UInt32(buf[o]) | (UInt32(buf[o + 1]) << 8) | (UInt32(buf[o + 2]) << 16) | (UInt32(buf[o + 3]) << 24)
    }

    private func parse() throws {
        // 从尾部找 EOCD (0x06054b50)
        let minEOCD = 22
        guard fileSize > minEOCD else { throw NSError(domain: "zip", code: 2) }
        var eocd = -1
        var i = fileSize - minEOCD
        let lowerBound = max(0, fileSize - minEOCD - 65535)
        while i >= lowerBound {
            if u32(i) == 0x0605_4b50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw NSError(domain: "zip", code: 3, userInfo: [NSLocalizedDescriptionKey: "不是有效 zip"]) }

        let count = Int(u16(eocd + 10))
        var off = Int(u32(eocd + 16))

        for _ in 0..<count {
            guard off + 46 <= buf.count, u32(off) == 0x0201_4b50 else { break }
            let method = u16(off + 10)
            let comp = Int(u32(off + 20))
            let uncomp = Int(u32(off + 24))
            let nameLen = Int(u16(off + 28))
            let extraLen = Int(u16(off + 30))
            let commentLen = Int(u16(off + 32))
            let lho = Int(u32(off + 42))
            guard off + 46 + nameLen <= buf.count else { break }
            let nameData = buf.subdata(in: (off + 46)..<(off + 46 + nameLen))
            let name = String(data: nameData, encoding: .utf8) ?? ""
            entries.append(Entry(name: name, compressedSize: comp, uncompressedSize: uncomp,
                                 method: method, localHeaderOffset: lho))
            off += 46 + nameLen + extraLen + commentLen
        }
    }

    // MARK: 读取

    func read(_ name: String) -> Data? {
        guard let e = entries.first(where: { $0.name == name }) else { return nil }
        return read(e)
    }

    func read(_ e: Entry) -> Data? {
        let lho = e.localHeaderOffset
        guard lho + 30 <= buf.count, u32(lho) == 0x0403_4b50 else { return nil }
        let nameLen = Int(u16(lho + 26))
        let extraLen = Int(u16(lho + 28))
        let dataStart = lho + 30 + nameLen + extraLen
        let dataEnd = dataStart + e.compressedSize
        guard dataEnd <= buf.count else { return nil }
        let raw = buf.subdata(in: dataStart..<dataEnd)

        if e.method == 0 { return raw }
        if e.method == 8 { return ZipArchive.inflateRaw(raw, expected: e.uncompressedSize) }
        return nil
    }

    // MARK: inflate（zlib）

    static func inflateRaw(_ data: Data, expected: Int) -> Data? {
        guard !data.isEmpty else { return Data() }
        var inBytes = [UInt8](data)
        var outBytes = [UInt8](repeating: 0, count: max(expected, 1024))
        var total: Int = 0
        let status: Int32 = inBytes.withUnsafeMutableBufferPointer { inBuf -> Int32 in
            outBytes.withUnsafeMutableBufferPointer { outBuf -> Int32 in
                var strm = z_stream()
                strm.next_in = inBuf.baseAddress
                strm.avail_in = uInt(inBuf.count)
                strm.next_out = outBuf.baseAddress
                strm.avail_out = uInt(outBuf.count)
                let ic = inflateInit2_(&strm, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
                guard ic == Z_OK else { return ic }
                defer { inflateEnd(&strm) }
                let r = inflate(&strm, Z_FINISH)
                total = Int(strm.total_out)
                return r
            }
        }
        guard status == Z_STREAM_END || status == Z_OK else { return nil }
        return Data(outBytes.prefix(total))
    }
}
