import UIKit

/// 把用户选的图缩成各种尺寸，准备替换 IPA 里的 AppIcon。
enum IconReplacer {

    /// 生成一套图标数据：尺寸(px) -> PNG
    static func generate(from image: UIImage) -> [Int: Data] {
        let sizes = [20, 29, 40, 58, 60, 76, 80, 87, 120, 152, 167, 180, 1024]
        var out: [Int: Data] = [:]
        for s in sizes {
            let size = CGSize(width: s, height: s)
            let r = UIGraphicsImageRenderer(size: size)
            let img = r.image { ctx in
                // 圆角裁剪（iOS 图标外观），实际系统还会再裁一次
                let path = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size),
                                        cornerRadius: CGFloat(s) * 0.22)
                path.addClip()
                image.draw(in: CGRect(origin: .zero, size: size))
            }
            if let d = img.pngData() { out[s] = d }
        }
        return out
    }

    /// 把 IPA 里所有 AppIcon*.png 替换成新图（按文件名的尺寸适配）
    static func apply(to appDir: URL, icon: UIImage, log: (String) -> Void) {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: appDir, includingPropertiesForKeys: nil) else { return }
        let set = generate(from: icon)
        var replaced = 0

        for case let url as URL in en {
            let name = url.lastPathComponent
            guard name.lowercased().hasSuffix(".png"),
                  name.lowercased().contains("appicon") else { continue }
            // 从文件名推尺寸：AppIcon60x60@3x -> 180
            let target = pixelSize(of: name)
            guard let target, let data = set[target] ?? set.nearest(to: target) else { continue }
            try? data.write(to: url)
            replaced += 1
        }
        log("替换了 \(replaced) 个图标文件")
        // 顺手删掉 Assets.car 里的旧图（iOS 会优先读 car，但删了会回落 PNG）
        let car = appDir.appendingPathComponent("Assets.car")
        if fm.fileExists(atPath: car.path) {
            // 保守：不删，只提示
            log("注意：Assets.car 仍含旧图，若图标没变说明系统优先用了它")
        }
    }

    /// AppIcon60x60@3x.png -> 180
    private static func pixelSize(of name: String) -> Int? {
        var nums: [Int] = []
        var cur = ""
        for ch in name {
            if ch.isNumber { cur.append(ch) }
            else if !cur.isEmpty { nums.append(Int(cur) ?? 0); cur = "" }
        }
        if !cur.isEmpty { nums.append(Int(cur) ?? 0) }
        guard nums.count >= 2 else { return nil }
        let scale = name.contains("@3x") ? 3 : (name.contains("@2x") ? 2 : 1)
        return nums[0] * scale
    }
}

private extension Dictionary where Key == Int, Value == Data {
    func nearest(to target: Int) -> Data? {
        let best = keys.min { abs($0 - target) < abs($1 - target) }
        return best.flatMap { self[$0] }
    }
}
