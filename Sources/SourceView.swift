import SwiftUI

/// 软件源：分类 + 中文名 + 下载即导入
struct SourceView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    struct Item: Codable, Identifiable {
        var id: String { bundleId.isEmpty ? name : bundleId }
        let name: String
        var cnName: String?
        let bundleId: String
        let version: String
        let size: String
        var icon: String?
        let url: String
        var notes: String?
        var cat: String?

        var title: String { (cnName?.isEmpty == false ? cnName! : name) }
        var category: String { cat?.isEmpty == false ? cat! : "其他" }
        var subName: String? { (cnName?.isEmpty == false && cnName != name) ? name : nil }
    }

    struct Feed: Codable {
        let updated: String?
        let items: [Item]
    }

    static let feedURL = "https://html.medwarp.cn/ipa/source.json"

    @State private var items: [Item] = []
    @State private var loading = true
    @State private var err: String?
    @State private var query = ""
    @State private var cat = "全部"
    @State private var busy: String?
    @State private var imported: Set<String> = []

    private var cats: [String] {
        var seen: [String] = ["全部"]
        for i in items where !seen.contains(i.category) { seen.append(i.category) }
        return seen
    }

    private var filtered: [Item] {
        var r = items
        if cat != "全部" { r = r.filter { $0.category == cat } }
        if !query.isEmpty {
            let q = query.lowercased()
            r = r.filter {
                $0.title.lowercased().contains(q) || $0.name.lowercased().contains(q)
                    || $0.bundleId.lowercased().contains(q)
            }
        }
        return r
    }

    private var grouped: [(String, [Item])] {
        var order: [String] = []
        var map: [String: [Item]] = [:]
        for i in filtered {
            if map[i.category] == nil { order.append(i.category) }
            map[i.category, default: []].append(i)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if !loading && err == nil {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(cats, id: \.self) { c in
                                Button {
                                    withAnimation(.easeOut(duration: 0.15)) { cat = c }
                                } label: {
                                    Text(c)
                                        .font(.system(size: 12.5, weight: cat == c ? .semibold : .regular))
                                        .padding(.horizontal, 13).padding(.vertical, 7)
                                        .background(cat == c ? Theme.accent : Theme.panel2)
                                        .foregroundColor(cat == c ? .white : .secondary)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 8)
                    }
                }

                ScrollView {
                    LazyVStack(spacing: 10) {
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
                            Text(query.isEmpty ? "这个分类下还没有应用" : "没搜到「\(query)」")
                                .font(.system(size: 13)).foregroundColor(.gray).padding(.vertical, 60)
                        } else {
                            ForEach(grouped, id: \.0) { group in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(group.0)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.secondary)
                                        .padding(.leading, 2)
                                    ForEach(group.1) { item in row(item) }
                                }
                                .padding(.bottom, 6)
                            }
                        }
                    }
                    .padding(16)
                }
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
        }
    }

    private func row(_ item: Item) -> some View {
        Card {
            HStack(spacing: 11) {
                iconView(item)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.system(size: 14.5, weight: .semibold)).lineLimit(1)
                    if let sub = item.subName {
                        Text(sub).font(.system(size: 10.5)).foregroundColor(.gray.opacity(0.75)).lineLimit(1)
                    }
                    Text("v\(item.version) · \(item.size)")
                        .font(.system(size: 11)).foregroundColor(.gray)
                    if let n = item.notes, !n.isEmpty {
                        Text(n).font(.system(size: 10.5)).foregroundColor(.gray.opacity(0.85)).lineLimit(1)
                    }
                }
                Spacer(minLength: 6)

                Button {
                    download(item)
                } label: {
                    Text(imported.contains(item.id) ? "已导入" : (busy == item.id ? "…" : "下载"))
                        .font(.system(size: 12.5, weight: .semibold))
                        .frame(minWidth: 54)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(imported.contains(item.id) ? Theme.panel2 : Theme.accent)
                        .foregroundColor(imported.contains(item.id) ? .secondary : .white)
                        .cornerRadius(9)
                }
                .disabled(busy != nil || imported.contains(item.id))
            }
        }
    }

    @ViewBuilder
    private func iconView(_ item: Item) -> some View {
        if let s = item.icon, !s.isEmpty, let u = URL(string: s) {
            AsyncImage(url: u) { phase in
                if let img = phase.image {
                    img.resizable().scaledToFill()
                } else { placeholder }
            }
        } else { placeholder }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [Theme.accent, Theme.accent2],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "app.dashed").font(.system(size: 20)).foregroundColor(.white)
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
                    items = try JSONDecoder().decode(Feed.self, from: data).items
                } catch {
                    err = "解析失败：\(error.localizedDescription)"
                }
            }
        }.resume()
    }

    private func download(_ item: Item) {
        guard let u = URL(string: item.url) else { return }
        busy = item.id
        URLSession.shared.downloadTask(with: u) { tmp, _, e in
            DispatchQueue.main.async {
                busy = nil
                guard let tmp, e == nil else { return }
                if (try? store.importIPA(from: tmp)) != nil {
                    imported.insert(item.id)
                }
            }
        }.resume()
    }
}
