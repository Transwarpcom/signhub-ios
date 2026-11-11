import SwiftUI

/// 看包结构：列出 IPA 里的文件树，可从中提取动态库
struct PackageBrowser: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let rec: IPARecord

    @State private var entries: [ZipArchive.Entry] = []
    @State private var loading = true
    @State private var extracting: String?
    @State private var msg: String?

    private var dylibs: [ZipArchive.Entry] {
        entries.filter { $0.name.lowercased().hasSuffix(".dylib") }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 12) {
                    Card(title: "概况") {
                        VStack(spacing: 6) {
                            row("文件数", "\(entries.count)")
                            row("总大小", fmtSize(entries.reduce(0) { $0 + $1.size }))
                            row("动态库", "\(dylibs.count) 个")
                        }
                    }

                    if !dylibs.isEmpty {
                        Card(title: "动态库（可提取）") {
                            VStack(spacing: 8) {
                                ForEach(dylibs, id: \.name) { e in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text((e.name as NSString).lastPathComponent)
                                                .font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                                            Text(e.name).font(.system(size: 9.5, design: .monospaced))
                                                .foregroundColor(.gray).lineLimit(1)
                                        }
                                        Spacer()
                                        Button {
                                            extract(e)
                                        } label: {
                                            Text(extracting == e.name ? "…" : "提取")
                                                .font(.system(size: 12, weight: .medium))
                                                .padding(.horizontal, 12).padding(.vertical, 6)
                                                .background(Theme.accent).cornerRadius(8)
                                        }
                                        .disabled(extracting != nil)
                                    }
                                }
                            }
                        }
                    }

                    Card(title: "文件树") {
                        if loading {
                            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 30)
                        } else {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(entries.prefix(400), id: \.name) { e in
                                    HStack(spacing: 6) {
                                        Text(e.name)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.gray).lineLimit(1)
                                        Spacer()
                                        Text(fmtSize(e.size))
                                            .font(.system(size: 9.5)).foregroundColor(.gray.opacity(0.7))
                                    }
                                }
                                if entries.count > 400 {
                                    Text("… 还有 \(entries.count - 400) 个文件")
                                        .font(.system(size: 11)).foregroundColor(.gray)
                                        .padding(.top, 6)
                                }
                            }
                        }
                    }

                    if let msg {
                        Card { Text(msg).font(.system(size: 12)).foregroundColor(.green) }
                    }
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("包结构")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
            .task { load() }
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.system(size: 12)).foregroundColor(.gray)
            Spacer()
            Text(v).font(.system(size: 12))
        }
    }

    private func load() {
        let url = store.ipaURL(rec)
        DispatchQueue.global(qos: .userInitiated).async {
            let list = (try? ZipArchive(path: url.path))?.entries ?? []
            DispatchQueue.main.async {
                entries = list.sorted { $0.name < $1.name }
                loading = false
            }
        }
    }

    private func extract(_ e: ZipArchive.Entry) {
        extracting = e.name
        let url = store.ipaURL(rec)
        DispatchQueue.global(qos: .userInitiated).async {
            defer { DispatchQueue.main.async { extracting = nil } }
            guard let z = try? ZipArchive(path: url.path),
                  let data = z.read(e) else { return }
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent((e.name as NSString).lastPathComponent)
            try? data.write(to: tmp)
            DispatchQueue.main.async {
                if let d = try? store.addDylib(from: tmp) {
                    msg = "已提取 \(d.name)（\(fmtSize(d.size))）"
                }
                try? FileManager.default.removeItem(at: tmp)
            }
        }
    }
}
