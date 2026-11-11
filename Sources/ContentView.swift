import SwiftUI
import UniformTypeIdentifiers

// MARK: - 根视图

struct ContentView: View {
    @StateObject private var store = AppStore.shared
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            WorkshopView().tag(0)
                .tabItem { Label("签名工坊", systemImage: "hammer") }
            SignedListView().tag(1)
                .tabItem { Label("应用", systemImage: "square.stack") }
            CertListView().tag(2)
                .tabItem { Label("证书库", systemImage: "checkmark.seal") }
            DylibListView().tag(3)
                .tabItem { Label("动态库", systemImage: "puzzlepiece") }
            SettingsView().tag(4)
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        .environmentObject(store)
        .preferredColorScheme(.dark)
    }
}

// MARK: - 主题

enum Theme {
    static let bg = Color(red: 0.04, green: 0.05, blue: 0.07)
    static let panel = Color(red: 0.07, green: 0.085, blue: 0.12)
    static let panel2 = Color(red: 0.09, green: 0.11, blue: 0.15)
    static let line = Color(red: 0.13, green: 0.16, blue: 0.22)
    static let accent = Color(red: 0.31, green: 0.49, blue: 1.0)
    static let accent2 = Color(red: 0.55, green: 0.36, blue: 0.96)
    static let ok = Color(red: 0.13, green: 0.72, blue: 0.4)
}

struct Card<C: View>: View {
    var title: String? = nil
    @ViewBuilder var content: () -> C
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title).font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.gray).textCase(.uppercase)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 1))
        .cornerRadius(16)
    }
}

struct PrimaryButton: View {
    let title: String
    var busy = false
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if busy { ProgressView().tint(.white) }
                Text(title).font(.system(size: 15, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(LinearGradient(colors: [Theme.accent, Theme.accent2],
                                       startPoint: .leading, endPoint: .trailing))
            .foregroundColor(.white)
            .cornerRadius(13)
        }
        .disabled(!enabled || busy)
        .opacity(enabled ? 1 : 0.45)
    }
}

func fmtSize(_ n: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
}

func fmtDate(_ d: Date) -> String {
    let f = DateFormatter(); f.dateFormat = "MM-dd HH:mm"; return f.string(from: d)
}

func tagView(_ s: String) -> some View {
    Text(s).font(.system(size: 10.5))
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Theme.panel2).cornerRadius(6).foregroundColor(.gray)
}

// MARK: - 签名工坊

struct WorkshopView: View {
    @EnvironmentObject var store: AppStore
    @State private var showImporter = false
    @State private var pending: IPARecord?
    @State private var showUrlSheet = false
    @State private var urlText = ""
    @State private var downloading = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 12) {
                    if store.ipas.isEmpty { emptyState }
                    else { ForEach(store.ipas) { ipaCard($0) } }
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("签名工坊")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button { showImporter = true } label: { Label("从本机选择 IPA", systemImage: "doc") }
                        Button { showUrlSheet = true } label: { Label("从网址下载", systemImage: "link") }
                        Button { scanFolder() } label: { Label("扫描文件夹", systemImage: "folder") }
                    } label: { Image(systemName: "plus.circle.fill").font(.system(size: 22)) }
                }
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [UTType(filenameExtension: "ipa") ?? .data],
                          allowsMultipleSelection: true) { handleImport($0) }
            .sheet(isPresented: $showUrlSheet) { urlSheet }
            .sheet(item: $pending) { rec in
                SignConfigView(ipa: rec).environmentObject(store)
            }
        }
        .navigationViewStyle(.stack)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "shippingbox").font(.system(size: 44)).foregroundColor(.gray)
            Text("还没有 IPA").font(.system(size: 16, weight: .semibold))
            Text("点右上角 + 从本机选，或扫描文件夹").font(.system(size: 13))
                .foregroundColor(.gray).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 80)
    }

    private func ipaCard(_ rec: IPARecord) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text(rec.displayName.isEmpty ? rec.fileName : rec.displayName)
                    .font(.system(size: 16, weight: .semibold)).lineLimit(1)
                Text(rec.bundleId).font(.system(size: 11.5)).foregroundColor(.gray).lineLimit(1)
                HStack(spacing: 6) {
                    tagView("v\(rec.version)")
                    tagView("iOS \(rec.minOS.isEmpty ? "?" : rec.minOS)+")
                    tagView("\(rec.fileCount) 文件")
                    tagView(fmtSize(rec.unzipSize))
                }
                if !rec.urlSchemes.isEmpty {
                    Text("URLScheme: " + rec.urlSchemes.joined(separator: ", "))
                        .font(.system(size: 11)).foregroundColor(.gray).lineLimit(1)
                }
                HStack(spacing: 8) {
                    Button { pending = rec } label: {
                        Text("签名").font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(Theme.accent).foregroundColor(.white).cornerRadius(10)
                    }
                    Button { pending = rec } label: {
                        Text("更多设置").font(.system(size: 13))
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(Theme.panel2).cornerRadius(10)
                    }
                }
            }
        }
        .contextMenu {
            Button(role: .destructive) { store.removeIPA(rec) } label: { Label("删除", systemImage: "trash") }
        }
    }

    private var urlSheet: some View {
        NavigationView {
            VStack(spacing: 14) {
                TextField("https://example.com/app.ipa", text: $urlText)
                    .autocapitalization(.none).disableAutocorrection(true)
                    .padding(12).background(Theme.panel2).cornerRadius(12)
                PrimaryButton(title: downloading ? "下载中…" : "下载", busy: downloading,
                              enabled: URL(string: urlText) != nil) { download() }
                Spacer()
            }
            .padding(16).background(Theme.bg.ignoresSafeArea())
            .navigationTitle("从网址下载").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { showUrlSheet = false } } }
        }
    }

    private func download() {
        guard let u = URL(string: urlText) else { return }
        downloading = true
        URLSession.shared.downloadTask(with: u) { tmp, _, err in
            defer { DispatchQueue.main.async { downloading = false } }
            guard let tmp, err == nil else { return }
            DispatchQueue.main.async {
                _ = try? store.importIPA(from: tmp)
                showUrlSheet = false
            }
        }.resume()
    }

    private func handleImport(_ res: Result<[URL], Error>) {
        guard case .success(let urls) = res else { return }
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: tmp)
            try? FileManager.default.copyItem(at: url, to: tmp)
            if scoped { url.stopAccessingSecurityScopedResource() }
            _ = try? store.importIPA(from: tmp)
            try? FileManager.default.removeItem(at: tmp)
        }
    }

    private func scanFolder() {
        guard let items = try? FileManager.default.contentsOfDirectory(at: store.root, includingPropertiesForKeys: nil) else { return }
        for u in items where u.pathExtension.lowercased() == "ipa" {
            _ = try? store.importIPA(from: u)
        }
    }
}

// MARK: - 已签名

struct SignedListView: View {
    @EnvironmentObject var store: AppStore
    @State private var action: IPARecord?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 12) {
                    if store.signed.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.seal").font(.system(size: 40)).foregroundColor(.gray)
                            Text("还没有签过包").foregroundColor(.gray)
                        }.frame(maxWidth: .infinity).padding(.vertical, 80)
                    } else {
                        ForEach(store.signed) { rec in
                            Card {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(rec.displayName.isEmpty ? rec.fileName : rec.displayName)
                                        .font(.system(size: 15.5, weight: .semibold)).lineLimit(1)
                                    Text(rec.bundleId).font(.system(size: 11)).foregroundColor(.gray).lineLimit(1)
                                    Text("v\(rec.version) · \(fmtSize(rec.unzipSize)) · \(fmtDate(rec.importedAt))")
                                        .font(.system(size: 11)).foregroundColor(.gray)
                                    HStack(spacing: 8) {
                                        Button {
                                            Installer.install(ipa: store.ipaURL(rec), bundleId: rec.bundleId)
                                        } label: {
                                            Text("安装到本机").font(.system(size: 13, weight: .semibold))
                                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                                                .background(Theme.ok).cornerRadius(10)
                                        }
                                        Button { action = rec } label: {
                                            Text("更多").font(.system(size: 13))
                                                .frame(width: 70).padding(.vertical, 10)
                                                .background(Theme.panel2).cornerRadius(10)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("已签名")
            .confirmationDialog("操作", isPresented: Binding(get: { action != nil }, set: { if !$0 { action = nil } })) {
                if let rec = action {
                    Button("分享 / 导出") { share(rec) }
                    Button("删除", role: .destructive) { store.removeIPA(rec) }
                }
                Button("取消", role: .cancel) {}
            }
        }
        .navigationViewStyle(.stack)
    }

    private func share(_ rec: IPARecord) {
        let u = store.ipaURL(rec)
        let av = UIActivityViewController(activityItems: [u], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(av, animated: true)
        }
    }
}

// MARK: - 证书库

struct CertListView: View {
    @EnvironmentObject var store: AppStore
    @State private var showAdd = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 12) {
                    if store.certs.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.seal").font(.system(size: 40)).foregroundColor(.gray)
                            Text("还没有证书").foregroundColor(.gray)
                        }.frame(maxWidth: .infinity).padding(.vertical, 80)
                    } else {
                        ForEach(store.certs) { certCard($0) }
                    }
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("证书库")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus.circle.fill").font(.system(size: 22)) }
                }
            }
            .sheet(isPresented: $showAdd) { AddCertView().environmentObject(store) }
        }
        .navigationViewStyle(.stack)
    }

    private func certCard(_ c: CertRecord) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(c.label).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    Spacer()
                    tagView(c.deviceCount > 0 ? "AdHoc · \(c.deviceCount) 台" : "AdHoc")
                }
                row("TeamID", c.teamId)
                row("AppID", c.appId)
                if let e = c.expireAt { row("证书到期", dateStr(e)) }
                if let e = c.profileExpireAt { row("描述到期", dateStr(e)) }
                HStack(spacing: 14) {
                    check("配对", true)
                    check("未过期", (c.expireAt ?? Date()) > Date())
                    check("未吊销", true)
                }.padding(.top, 2)
            }
        }
        .contextMenu {
            Button(role: .destructive) { store.removeCert(c) } label: { Label("删除", systemImage: "trash") }
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.system(size: 11)).foregroundColor(.gray)
            Spacer()
            Text(v.isEmpty ? "—" : v).font(.system(size: 11)).foregroundColor(.gray).lineLimit(1)
        }
    }

    private func check(_ label: String, _ ok: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 11)).foregroundColor(ok ? Theme.ok : .red)
            Text(label).font(.system(size: 11)).foregroundColor(.gray)
        }
    }

    private func dateStr(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; return f.string(from: d)
    }
}

// MARK: - 添加证书

struct AddCertView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var p12: URL?
    @State private var mp: URL?
    @State private var password = ""
    @State private var label = ""
    @State private var picking: String?
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 12) {
                    Card(title: "证书文件") {
                        VStack(spacing: 10) {
                            fileRow(p12?.lastPathComponent ?? "选择 .p12", "证书 + 私钥", "key") { picking = "p12" }
                            fileRow(mp?.lastPathComponent ?? "选择 .mobileprovision", "描述文件", "doc.text") { picking = "mp" }
                        }
                    }
                    Card(title: "信息") {
                        VStack(spacing: 10) {
                            SecureField("p12 密码", text: $password)
                                .padding(12).background(Theme.panel2).cornerRadius(12)
                            TextField("备注名（可选）", text: $label)
                                .padding(12).background(Theme.panel2).cornerRadius(12)
                            if let error { Text(error).font(.system(size: 12)).foregroundColor(.red) }
                        }
                    }
                    PrimaryButton(title: "保存证书", busy: busy, enabled: p12 != nil && mp != nil) { save() }
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("添加证书").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
            .fileImporter(isPresented: Binding(get: { picking != nil }, set: { if !$0 { picking = nil } }),
                          allowedContentTypes: [.data], allowsMultipleSelection: false) { res in
                guard case .success(let urls) = res, let u = urls.first else { picking = nil; return }
                let scoped = u.startAccessingSecurityScopedResource()
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(u.lastPathComponent)
                try? FileManager.default.removeItem(at: tmp)
                try? FileManager.default.copyItem(at: u, to: tmp)
                if scoped { u.stopAccessingSecurityScopedResource() }
                if picking == "p12" { p12 = tmp } else { mp = tmp }
                picking = nil
            }
        }
    }

    private func fileRow(_ title: String, _ sub: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 16)).foregroundColor(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13.5, weight: .medium)).lineLimit(1)
                    Text(sub).font(.system(size: 11)).foregroundColor(.gray)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11)).foregroundColor(.gray)
            }
            .padding(12).background(Theme.panel2).cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    private func save() {
        guard let p12, let mp else { return }
        busy = true; error = nil
        do {
            _ = try store.addCert(p12: p12, profile: mp, password: password, label: label)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        busy = false
    }
}

// MARK: - 动态库

struct DylibListView: View {
    @EnvironmentObject var store: AppStore
    @State private var showImporter = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 12) {
                    if store.dylibs.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "puzzlepiece").font(.system(size: 40)).foregroundColor(.gray)
                            Text("还没有存过动态库").foregroundColor(.gray)
                            Text("导入 .dylib 后，签名时可一键注入").font(.system(size: 12)).foregroundColor(.gray)
                        }.frame(maxWidth: .infinity).padding(.vertical, 80)
                    } else {
                        ForEach(store.dylibs) { d in
                            Card {
                                Text(d.name).font(.system(size: 14, weight: .medium)).lineLimit(1)
                                Text(fmtSize(d.size)).font(.system(size: 11)).foregroundColor(.gray)
                            }
                            .contextMenu {
                                Button(role: .destructive) { store.removeDylib(d) } label: { Label("删除", systemImage: "trash") }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("动态库")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showImporter = true } label: { Image(systemName: "plus.circle.fill").font(.system(size: 22)) }
                }
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [UTType(filenameExtension: "dylib") ?? .data],
                          allowsMultipleSelection: true) { res in
                guard case .success(let urls) = res else { return }
                for u in urls {
                    let scoped = u.startAccessingSecurityScopedResource()
                    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(u.lastPathComponent)
                    try? FileManager.default.removeItem(at: tmp)
                    try? FileManager.default.copyItem(at: u, to: tmp)
                    if scoped { u.stopAccessingSecurityScopedResource() }
                    _ = try? store.addDylib(from: tmp)
                    try? FileManager.default.removeItem(at: tmp)
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - 设置

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 12) {
                    Card(title: "存储") {
                        VStack(spacing: 8) {
                            row("IPA", "\(store.ipas.count) 个")
                            row("已签名", "\(store.signed.count) 个")
                            row("证书", "\(store.certs.count) 张")
                            row("动态库", "\(store.dylibs.count) 个")
                        }
                    }
                    Card(title: "关于") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("签名工坊").font(.system(size: 14, weight: .semibold))
                            Text("zsign 内核 · 本地重签名 · OTA 安装")
                                .font(.system(size: 12)).foregroundColor(.gray)
                            Text("证书、IPA、动态库全部存在本机沙盒，不上传服务器。")
                                .font(.system(size: 11.5)).foregroundColor(.gray)
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("设置")
        }
        .navigationViewStyle(.stack)
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.system(size: 13))
            Spacer()
            Text(v).font(.system(size: 13)).foregroundColor(.gray)
        }
    }
}
