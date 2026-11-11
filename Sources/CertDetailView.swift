import SwiftUI

/// 证书详情：41 项 entitlements + 设为当前证书
struct CertDetailView: View {
    @EnvironmentObject var store: AppStore
    let cert: CertRecord
    @State private var isCurrent = false
    @State private var showAll = false
    @State private var confirmDelete = false
    @State private var checking = false
    @State private var revokeText: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                setCurrentCard
                basicCard
                profileCard
                entCard
                exportCard
                revokeCard
                deleteCard
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(cert.label)
        .navigationBarTitleDisplayMode(.inline)
        .alert("删除这张证书？", isPresented: $confirmDelete) {
            Button("删除", role: .destructive) {
                store.removeCert(cert)
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("会同时删掉沙盒里的 p12 和描述文件，不可恢复。")
        }
        .onAppear {
            store.ensureCurrentCert()
            isCurrent = UserDefaults.standard.string(forKey: "hub.currentCert") == cert.id
        }
    }

    private var setCurrentCard: some View {
        Button {
            UserDefaults.standard.set(cert.id, forKey: "hub.currentCert")
            isCurrent = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isCurrent ? "checkmark.circle.fill" : "circle")
                Text(isCurrent ? "当前证书" : "设为当前证书")
                    .font(.system(size: 15, weight: .semibold))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 13)
            .background(isCurrent ? Theme.ok : Theme.accent)
            .foregroundColor(.white).cornerRadius(13)
        }
        .buttonStyle(.plain)
    }

    private var basicCard: some View {
        Card(title: "证书") {
            VStack(spacing: 8) {
                row("主体", cert.subjectCN.isEmpty ? cert.label : cert.subjectCN)
                row("TeamID", cert.teamId)
                row("有效期至", cert.expireAt.map(dateStr) ?? "—")
                if let e = cert.expireAt {
                    row("剩余", "\(max(0, Int(e.timeIntervalSinceNow / 86400))) 天")
                }
                HStack(spacing: 14) {
                    check("配对", true)
                    check("未过期", (cert.expireAt ?? Date()) > Date())
                    check("未吊销", true)
                }.padding(.top, 2)
            }
        }
    }

    private var profileCard: some View {
        Card(title: "描述文件") {
            VStack(spacing: 8) {
                row("AppID", cert.appId)
                row("UUID", cert.uuid)
                row("类型", cert.deviceCount > 0 ? "AdHoc · 白名单 \(cert.deviceCount) 台" : "AdHoc")
                row("到期", cert.profileExpireAt.map(dateStr) ?? "—")
            }
        }
    }

    private var entCard: some View {
        Card(title: "权限（\(cert.entitlements.count) 项）") {
            VStack(spacing: 0) {
                let list = showAll ? cert.entitlements : Array(cert.entitlements.prefix(8))
                ForEach(list) { e in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(EntitlementNames.display(e.key))
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(.primary).lineLimit(2)
                        Text(e.key)
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundColor(.gray.opacity(0.7)).lineLimit(2)
                        Text(e.value)
                            .font(.system(size: 12.5))
                            .foregroundColor(e.value == "是" ? Theme.ok : .primary)
                            .lineLimit(3)
                        Divider().background(Theme.line).padding(.vertical, 6)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if cert.entitlements.count > 8 {
                    Button {
                        withAnimation { showAll.toggle() }
                    } label: {
                        Text(showAll ? "收起" : "展开全部 \(cert.entitlements.count) 项")
                            .font(.system(size: 13, weight: .medium))
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                }
            }
        }
    }

    private var exportCard: some View {
        Card(title: "导出") {
            VStack(alignment: .leading, spacing: 8) {
                Text("直接分享 p12 和 mobileprovision 两个文件。p12 密码就是导入时填的那个。")
                    .font(.system(size: 12)).foregroundColor(.gray)
                Button {
                    exportPack()
                } label: {
                    Label("导出证书包", systemImage: "square.and.arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(Theme.panel2).cornerRadius(10)
                }
            }
        }
    }

    private func exportPack() {
        let p12 = store.p12URL(cert)
        let prof = store.profileURL(cert)
        var items: [Any] = []
        if FileManager.default.fileExists(atPath: p12.path) { items.append(p12) }
        if FileManager.default.fileExists(atPath: prof.path) { items.append(prof) }
        guard !items.isEmpty else { return }
        let av = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(av, animated: true)
        }
    }

    private var revokeCard: some View {
        Card(title: "吊销检查（联网）") {
            VStack(alignment: .leading, spacing: 8) {
                if let t = revokeText {
                    Text(t).font(.system(size: 12.5)).foregroundColor(.gray)
                } else {
                    Text("请求 Apple OCSP 验证这张证书当前是否有效").font(.system(size: 12)).foregroundColor(.gray)
                }
                Button {
                    check()
                } label: {
                    HStack(spacing: 6) {
                        if checking { ProgressView().tint(.white).scaleEffect(0.8) }
                        Text(checking ? "查询中…" : "开始检查").font(.system(size: 13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(Theme.accent).cornerRadius(10)
                }
                .disabled(checking)
            }
        }
    }

    private func check() {
        checking = true
        revokeText = nil
        let p12 = store.p12URL(cert)
        RevocationChecker.check(p12: p12, password: cert.password) { st in
            checking = false
            switch st {
            case .valid:
                revokeText = "✅ 未被吊销（OCSP 返回 good）"
            case .revoked:
                revokeText = "❌ 证书已被 Apple 吊销，签出来的包装不上"
            case .unknown(let m):
                revokeText = "⚠️ 查询失败：\(m)"
            }
        }
    }

    private var deleteCard: some View {
        Button {
            confirmDelete = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "trash")
                Text("删除这张证书").font(.system(size: 14, weight: .medium))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 13)
            .background(Color.red.opacity(0.15))
            .foregroundColor(.red)
            .cornerRadius(13)
        }
        .buttonStyle(.plain)
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).font(.system(size: 12)).foregroundColor(.gray)
            Spacer()
            Text(v.isEmpty ? "—" : v)
                .font(.system(size: 12)).foregroundColor(.primary)
                .multilineTextAlignment(.trailing).lineLimit(2)
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
