import SwiftUI

/// 软件源：从服务器拉应用清单，支持搜索，点下载直接进签名工坊
struct SourceView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    struct Item: Codable, Identifiable {
        var id: String { bundleId.isEmpty ? name : bundleId }
        let name: String
        let bundleId: String
        let version: String
        let size: String
        let icon: String?
        let url: String
        let notes: String?
    }

    struct Feed: Codable {
        let updated: String?
        let items: [Item]
    }

    /// 源地址（可改）
    static let feedURL = "https://html.medwarp.cn/ipa/source.json"

    @State private var items: [Item] = []
    @State private var loading = true
    @State private var err: String?
    @State private var query = ""
    @State private var downloading: String?
    @State private var done = 0

    private var filtered: [Item] {
        guard !query.isEmpty else { return items }
        let q = query.lowercased()
        return items.filter { $0.name.lowercased().contains(q) || $0.bundleId.lowercased().contains(q) }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 10) {
                    if loading {
                        ProgressView().padding(.vertical, 60)
                    } else if let err {
                        VStack(spacing: 10) {
                            Image(systemName: "wifi.exclamationmark").font(.system(size: 36)).foregroundColor(.gray)
                            Text("加载失败").font(.system(size: 15, weight: .semibold))
                            Text(err).font(.system(size: 11)).foregroundColor(.gray).multilineTextAlignment(.center)
                            Button("重试") { load() }
                                .font(.system(size: 13, weight: .medium))
                                .padding(.horizontal, 20).padding(.vertical, 9)
                                .background(Theme.accent).cornerRadius(10)
                        }
                        .padding(.vertical, 60)
                    } else if filtered.isEmpty {
                        Text(query.isEmpty ? "源里还没有应用" : "没搜到「\(query)」")
                            .font(.system(size: 13)).foregroundColor(.gray).padding(.vertical, 60)
                    } else {
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, item in
                            row(item, rank: idx + 1)
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("软件源")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "搜应用名或 Bundle ID")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { load() } label: { Image(systemName: "arrow.clockwise") }
                }
            }
            .task { load() }
            .overlay(alignment: .bottom) {
                if let d = downloading {
                    Text("正在下载 \(d)…").font(.system(size: 12))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Theme.panel2).cornerRadius(20)
                        .padding(.bottom, 20)
                }
            }
        }
    }

    private func row(_ item: Item, rank: Int) -> some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                // 排名徽章（前三）
                ZStack {
                    if let url = item.icon, let u = URL(string: url) {
                        AsyncImage(url: u) { phase in
                            if let img = phase.image {
                                img.resizable().scaledToFill()
                            } else {
                                placeholderIcon
                            }
                        }
                    } else {
                        placeholderIcon
                    }
                }
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if rank <= 3 {
                        Text("\(rank)")
                            .font(.system(size: 9, weight: .bold))
                            .frame(width: 16, height: 16)
                            .background(rank == 1 ? Color.yellow : (rank == 2 ? Color.gray : Color.orange))
                            .foregroundColor(.black)
                            .clipShape(Circle())
                            .offset(x: -5, y: -5)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    Text("v\(item.version) · \(item.size)")
                        .font(.system(size: 11)).foregroundColor(.gray)
                    Text(item.bundleId)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.gray.opacity(0.7)).lineLimit(1)
                    if let n = item.notes {
                        Text(n).font(.system(size: 10.5)).foregroundColor(.gray.opacity(0.8)).lineLimit(2)
                    }
                }
                Spacer()

                Button {
                    download(item)
                } label: {
                    Text(downloading == item.name ? "…" : "下载")
                        .font(.system(size: 12.5, weight: .semibold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Theme.accent).cornerRadius(9)
                }
                .disabled(downloading != nil)
            }
        }
    }

    private var placeholderIcon: some View {
        ZStack {
            LinearGradient(colors: [Theme.accent, Theme.accent2],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "app.dashed").font(.system(size: 22)).foregroundColor(.white)
        }
    }

    private func load() {
        loading = true
        err = nil
        guard let u = URL(string: Self.feedURL) else { err = "源地址无效"; loading = false; return }
        var req = URLRequest(url: u)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 20
        URLSession.shared.dataTask(with: req) { data, _, e in
            DispatchQueue.main.async {
                loading = false
                if let e { err = e.localizedDescription; return }
                guard let data else { err = "没有数据"; return }
                do {
                    let feed = try JSONDecoder().decode(Feed.self, from: data)
                    items = feed.items
                } catch {
                    err = "解析失败：\(error.localizedDescription)"
                }
            }
        }.resume()
    }

    private func download(_ item: Item) {
        guard let u = URL(string: item.url) else { return }
        downloading = item.name
        URLSession.shared.downloadTask(with: u) { tmp, _, e in
            defer { DispatchQueue.main.async { downloading = nil } }
            guard let tmp, e == nil else { return }
            DispatchQueue.main.async {
                _ = try? store.importIPA(from: tmp)
                done += 1
            }
        }.resume()
    }
}
