import SwiftUI

/// 证书详情：41 项 entitlements + 设为当前证书
struct CertDetailView: View {
    @EnvironmentObject var store: AppStore
    let cert: CertRecord
    @State private var isCurrent = false
    @State private var showAll = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                setCurrentCard
                basicCard
                profileCard
                entCard
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(cert.label)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
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
                        Text(e.key)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.gray).lineLimit(2)
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
