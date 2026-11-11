import SwiftUI
import UIKit

/// IPA 图标提取 + 缓存。列表里每个包显示自己的图标。
@MainActor
final class IconCache {
    static let shared = IconCache()
    private var mem: [String: UIImage] = [:]
    private let dir: URL

    init() {
        dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("icons")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func icon(for ipa: URL, id: String) -> UIImage? {
        if let m = mem[id] { return m }
        let cached = dir.appendingPathComponent("\(id).png")
        if let d = try? Data(contentsOf: cached), let img = UIImage(data: d) {
            mem[id] = img
            return img
        }
        guard let img = extract(ipa) else { return nil }
        mem[id] = img
        if let d = img.pngData() { try? d.write(to: cached) }
        return img
    }

    /// 从 IPA 里挑最大的 AppIcon*.png
    private func extract(_ ipa: URL) -> UIImage? {
        guard let z = try? ZipArchive(path: ipa.path) else { return nil }
        // 候选：AppIcon60x60@3x.png / @2x / AppIcon76x76@2x~ipad.png / iTunesArtwork
        let candidates = z.entries.filter {
            let n = $0.name.lowercased()
            return n.hasSuffix(".png") && (n.contains("appicon") || n.contains("itunesartwork"))
        }
        guard !candidates.isEmpty else { return nil }
        // 按文件名里的尺寸排序，取最大的
        let sorted = candidates.sorted { a, b in
            sizeScore(a.name) > sizeScore(b.name)
        }
        for e in sorted {
            if let d = z.read(e), let img = UIImage(data: d) {
                return img
            }
        }
        return nil
    }

    private func sizeScore(_ name: String) -> Int {
        // 从文件名里抠数字：AppIcon60x60@3x -> 180
        var nums: [Int] = []
        var cur = ""
        for ch in name {
            if ch.isNumber { cur.append(ch) }
            else if !cur.isEmpty { nums.append(Int(cur) ?? 0); cur = "" }
        }
        if !cur.isEmpty { nums.append(Int(cur) ?? 0) }
        guard nums.count >= 2 else { return 0 }
        let scale = name.contains("@3x") ? 3 : (name.contains("@2x") ? 2 : 1)
        return nums[0] * nums[1] * scale
    }
}

struct AppIconView: View {
    let ipa: URL
    let id: String
    var size: CGFloat = 52

    @State private var img: UIImage?

    var body: some View {
        Group {
            if let img {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [Theme.accent, Theme.accent2],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "app").font(.system(size: size * 0.4)).foregroundColor(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.23, style: .continuous))
        .task {
            img = IconCache.shared.icon(for: ipa, id: id)
        }
    }
}
