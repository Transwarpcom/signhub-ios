import SwiftUI

// MARK: - 签名配置

struct SignConfigView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let ipa: IPARecord

    @State private var certId = ""
    @State private var opts = SignOptions()
    @State private var signing = false
    @State private var log = ""
    @State private var result: IPARecord?
    @State private var error: String?
    @State private var showAdvanced = false
    @State private var prog: Double = 0
    @State private var pickIcon = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 12) {
                    infoCard
                    certCard
                    basicCard
                    advancedCard
                    if !log.isEmpty { logCard }
                    if let result { resultCard(result) }
                    if let error {
                        Card { Text(error).font(.system(size: 12)).foregroundColor(.red) }
                    }
                    if signing {
                        VStack(spacing: 6) {
                            ProgressView(value: prog)
                                .tint(Theme.accent)
                            Text("\(Int(prog * 100))%")
                                .font(.system(size: 11)).foregroundColor(.gray)
                        }
                        .padding(.horizontal, 4)
                    }
                    PrimaryButton(title: signing ? "签名中…" : "签名", busy: signing,
                                  enabled: !certId.isEmpty) { start() }
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("签名配置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
            .documentPicker(isPresented: $pickIcon) { urls in
                if let u = urls.first { opts.iconPath = u.path }
            }
        }
        .onAppear {
            if certId.isEmpty { certId = store.certs.first?.id ?? "" }
        }
    }

    private var infoCard: some View {
        Card(title: "包信息") {
            VStack(alignment: .leading, spacing: 6) {
                Text(ipa.displayName.isEmpty ? ipa.fileName : ipa.displayName)
                    .font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Text(ipa.bundleId).font(.system(size: 11)).foregroundColor(.gray).lineLimit(1)
                HStack(spacing: 6) {
                    tagView("v\(ipa.version)")
                    tagView("iOS \(ipa.minOS)+")
                    tagView(fmtSize(ipa.unzipSize))
                }
            }
        }
    }

    private var certCard: some View {
        Card(title: "证书") {
            if store.certs.isEmpty {
                Text("证书库是空的，先去「证书库」添加").font(.system(size: 13)).foregroundColor(.orange)
            } else {
                Picker("证书", selection: $certId) {
                    ForEach(store.certs) { c in
                        Text("\(c.label) · \(c.teamId)").tag(c.id)
                    }
                }
                .pickerStyle(.menu)
                if let c = store.certs.first(where: { $0.id == certId }) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AppID: \(c.appId)").font(.system(size: 10.5)).foregroundColor(.gray).lineLimit(1)
                        Text("白名单 \(c.deviceCount) 台").font(.system(size: 10.5)).foregroundColor(.gray)
                    }
                }
            }
        }
    }

    private var basicCard: some View {
        Card(title: "基础") {
            VStack(spacing: 10) {
                field("显示名称（留空不改）", text: $opts.newName)
                field("Bundle ID（留空不改）", text: $opts.newBundleId)
                field("版本号（留空不改）", text: $opts.newVersion)
                HStack {
                    Text("多开份数").font(.system(size: 13))
                    Spacer()
                    Stepper("\(opts.cloneCount)", value: $opts.cloneCount, in: 1...10)
                        .labelsHidden()
                    Text("\(opts.cloneCount)").font(.system(size: 13)).frame(width: 24)
                }
            }
        }
    }

    private var advancedCard: some View {
        Card(title: "高级") {
            VStack(spacing: 10) {
                toggleRow("移除插件（PlugIns/appex）", $opts.removePlugins)
                toggleRow("移除 Watch App", $opts.removeWatch)
                toggleRow("清掉旧的 _CodeSignature", $opts.clearOldCodeSignature)
                field("最低 iOS 版本（如 15.0）", text: $opts.newMinOS)
                Button {
                    pickIcon = true
                } label: {
                    HStack {
                        Image(systemName: "photo")
                        Text(opts.iconPath.isEmpty ? "换图标" : "已选图标（点重选）")
                            .font(.system(size: 13))
                        Spacer()
                        if !opts.iconPath.isEmpty {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(Theme.ok)
                        }
                    }
                    .padding(11).background(Theme.panel2).cornerRadius(11)
                }
                .buttonStyle(.plain)
                if !store.dylibs.isEmpty {
                    Text("注入动态库").font(.system(size: 12)).foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(store.dylibs) { d in
                        Button {
                            if let i = opts.dylibIds.firstIndex(of: d.id) { opts.dylibIds.remove(at: i) }
                            else { opts.dylibIds.append(d.id) }
                        } label: {
                            HStack {
                                Image(systemName: opts.dylibIds.contains(d.id) ? "checkmark.square.fill" : "square")
                                    .foregroundColor(opts.dylibIds.contains(d.id) ? Theme.accent : .gray)
                                Text(d.name).font(.system(size: 12.5)).lineLimit(1)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var logCard: some View {
        Card(title: "日志") {
            Text(log).font(.system(size: 10.5, design: .monospaced))
                .foregroundColor(Color(red: 0.6, green: 0.78, blue: 0.6))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func resultCard(_ r: IPARecord) -> some View {
        Card(title: "完成") {
            VStack(spacing: 8) {
                Text(r.displayName.isEmpty ? r.fileName : r.displayName)
                    .font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text("\(r.bundleId) · v\(r.version) · \(fmtSize(r.unzipSize))")
                    .font(.system(size: 11)).foregroundColor(.gray).lineLimit(1)
                HStack(spacing: 8) {
                    Button {
                        Installer.install(ipa: store.ipaURL(r), bundleId: r.bundleId)
                    } label: {
                        Text("安装到本机").font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 11)
                            .background(Theme.ok).cornerRadius(10)
                    }
                    Button { share(r) } label: {
                        Text("分享").font(.system(size: 13))
                            .frame(width: 70).padding(.vertical, 11)
                            .background(Theme.panel2).cornerRadius(10)
                    }
                }
            }
        }
    }

    private func toggleRow(_ title: String, _ binding: Binding<Bool>) -> some View {
        Toggle(title, isOn: binding)
            .font(.system(size: 13))
            .toggleStyle(SwitchToggleStyle(tint: Theme.accent))
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .autocapitalization(.none).disableAutocorrection(true)
            .padding(11).background(Theme.panel2).cornerRadius(11)
            .font(.system(size: 13.5))
    }

    // MARK: 执行

    private func start() {
        guard let cert = store.certs.first(where: { $0.id == certId }) else { return }
        signing = true; error = nil; result = nil; log = ""; prog = 0

        let input = store.ipaURL(ipa)
        let outName = "signed-\(Int(Date().timeIntervalSince1970)).ipa"
        let out = store.signedDir.appendingPathComponent(outName)
        let p12 = store.p12URL(cert)
        let prof = store.profileURL(cert)
        let dylibPaths = opts.dylibIds.compactMap { id in
            store.dylibs.first(where: { $0.id == id }).map { store.dylibsDir.appendingPathComponent($0.path) }
        }
        let o = opts

        DispatchQueue.global(qos: .userInitiated).async {
            var last: URL?
            var logs: [String] = []
            for i in 0..<max(1, o.cloneCount) {
                let dst = i == 0 ? out : store.signedDir.appendingPathComponent("signed-\(Int(Date().timeIntervalSince1970))-\(i).ipa")
                var bundle = o.newBundleId
                if o.cloneCount > 1 {
                    let base = bundle.isEmpty ? ipa.bundleId : bundle
                    bundle = i == 0 ? base : "\(base).\(i)"
                }
                let r = Signer.sign(ipa: input, p12: p12, password: cert.password, profile: prof,
                                    output: dst,
                                    bundleId: bundle.isEmpty ? nil : bundle,
                                    displayName: o.newName.isEmpty ? nil : o.newName,
                                    version: o.newVersion.isEmpty ? nil : o.newVersion,
                                    minOS: o.newMinOS.isEmpty ? nil : o.newMinOS,
                                    removePlugins: o.removePlugins,
                                    removeWatch: o.removeWatch,
                                    dylibs: dylibPaths,
                                    iconPath: o.iconPath.isEmpty ? nil : o.iconPath,
                                    progress: { p in DispatchQueue.main.async { prog = p } },
                                    logHandler: { logs.append($0) })
                if r.ok { last = dst }
            }
            DispatchQueue.main.async {
                signing = false
                log = logs.joined(separator: "\n")
                if let last {
                    let meta = AppStore.inspectIPA(last)
                    let rec = IPARecord(id: UUID().uuidString.prefix(8).lowercased(),
                                        fileName: last.lastPathComponent,
                                        bundleId: meta.bundleId,
                                        displayName: meta.displayName,
                                        version: meta.version,
                                        minOS: meta.minOS,
                                        fileCount: meta.fileCount,
                                        unzipSize: meta.unzipSize,
                                        urlSchemes: meta.urlSchemes,
                                        importedAt: Date(),
                                        isSigned: true)
                    store.registerSigned(rec)
                    result = rec
                } else {
                    error = "签名失败，看日志"
                }
            }
        }
    }

    private func share(_ r: IPARecord) {
        let av = UIActivityViewController(activityItems: [store.ipaURL(r)], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(av, animated: true)
        }
    }
}
