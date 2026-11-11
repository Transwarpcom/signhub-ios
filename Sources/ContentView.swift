import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var ipaURL: URL?
    @State private var p12URL: URL?
    @State private var mpURL: URL?
    @State private var password = ""
    @State private var bundleId = ""
    @State private var displayName = ""
    @State private var version = ""

    @State private var signing = false
    @State private var log = ""
    @State private var resultURL: URL?
    @State private var installURL: String?
    @State private var errorText: String?

    @State private var showPicker: PickerKind?
    @State private var server = LocalServer()

    enum PickerKind: String, Identifiable {
        case ipa, p12, mp
        var id: String { rawValue }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    fileCard
                    certCard
                    actionCard
                    if !log.isEmpty { logCard() }
                    if let resultURL { resultCard(resultURL) }
                }
                .padding(16)
            }
            .background(Color(red: 0.04, green: 0.05, blue: 0.07).ignoresSafeArea())
            .navigationBarHidden(true)
        }
        .navigationViewStyle(.stack)
        .fileImporter(
            isPresented: Binding(
                get: { showPicker != nil },
                set: { if !$0 { showPicker = nil } }
            ),
            allowedContentTypes: allowedTypes,
            allowsMultipleSelection: false
        ) { res in
            defer { showPicker = nil }
            guard case .success(let urls) = res, let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            // 拷到沙盒，避免后续读不到
            let dst = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: dst)
            try? FileManager.default.copyItem(at: url, to: dst)
            switch showPicker {
            case .ipa: ipaURL = dst
            case .p12: p12URL = dst
            case .mp: mpURL = dst
            case .none: break
            }
        }
    }

    private var allowedTypes: [UTType] {
        switch showPicker {
        case .ipa: return [UTType(filenameExtension: "ipa") ?? .data]
        case .p12: return [UTType(filenameExtension: "p12") ?? .data]
        case .mp: return [UTType(filenameExtension: "mobileprovision") ?? .data]
        case .none: return [.data]
        }
    }

    // MARK: - 区块

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(LinearGradient(colors: [Color(red: 0.31, green: 0.49, blue: 1), Color(red: 0.55, green: 0.36, blue: 0.96)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 46, height: 46)
                Text("🔏").font(.system(size: 22))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("SignHub").font(.system(size: 20, weight: .bold))
                Text("zsign 内核 · 本地重签名").font(.system(size: 12)).foregroundColor(.gray)
            }
            Spacer()
        }
    }

    private var fileCard: some View {
        card("1 · 选择 IPA") {
            fileRow(title: ipaURL?.lastPathComponent ?? "点击选择 .ipa", sub: "待签名的安装包", icon: "📦") {
                showPicker = .ipa
            }
        }
    }

    private var certCard: some View {
        card("2 · 证书与描述文件") {
            VStack(spacing: 10) {
                fileRow(title: p12URL?.lastPathComponent ?? "选择 .p12", sub: "证书 + 私钥", icon: "🔑") {
                    showPicker = .p12
                }
                fileRow(title: mpURL?.lastPathComponent ?? "选择 .mobileprovision", sub: "描述文件", icon: "📄") {
                    showPicker = .mp
                }
                SecureField("p12 密码", text: $password)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(Color(red: 0.09, green: 0.11, blue: 0.15))
                    .cornerRadius(12)
            }
        }
    }

    private var actionCard: some View {
        card("3 · 签名") {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    field("显示名称", text: $displayName)
                    field("Bundle ID", text: $bundleId)
                }
                field("版本号", text: $version)

                Button {
                    startSign()
                } label: {
                    HStack {
                        if signing { ProgressView().tint(.white) }
                        Text(signing ? "签名中…" : "开始签名")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(LinearGradient(colors: [Color(red: 0.31, green: 0.49, blue: 1), Color(red: 0.55, green: 0.36, blue: 0.96)],
                                               startPoint: .leading, endPoint: .trailing))
                    .foregroundColor(.white)
                    .cornerRadius(13)
                }
                .disabled(!canSign || signing)
                .opacity(canSign ? 1 : 0.45)

                if let errorText {
                    Text(errorText).font(.system(size: 12)).foregroundColor(.red)
                }
            }
        }
    }

    private func resultCard(_ url: URL) -> some View {
        card("签名完成") {
            VStack(alignment: .leading, spacing: 10) {
                Text(url.lastPathComponent).font(.system(size: 14, weight: .semibold))
                Text(byteText(url)).font(.system(size: 12)).foregroundColor(.gray)
                HStack(spacing: 8) {
                    ShareLink(item: url) {
                        Text("导出 IPA")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 11)
                            .background(Color(red: 0.09, green: 0.11, blue: 0.15))
                            .cornerRadius(11)
                    }
                    if let installURL {
                        Button {
                            openInstall(installURL)
                        } label: {
                            Text("安装到本机")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(maxWidth: .infinity).padding(.vertical, 11)
                                .background(Color(red: 0.13, green: 0.55, blue: 0.28))
                                .cornerRadius(11)
                        }
                    }
                }
            }
        }
    }

    private func logCard() -> some View {
        card("日志") {
            Text(log)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Color(red: 0.6, green: 0.75, blue: 0.6))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 组件

    private func card<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundColor(.gray)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.07, green: 0.085, blue: 0.12))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(red: 0.13, green: 0.16, blue: 0.22), lineWidth: 1))
        .cornerRadius(16)
    }

    private func fileRow(title: String, sub: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(icon).font(.system(size: 20))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                    Text(sub).font(.system(size: 11)).foregroundColor(.gray)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundColor(.gray)
            }
            .padding(12)
            .background(Color(red: 0.09, green: 0.11, blue: 0.15))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .autocapitalization(.none)
            .disableAutocorrection(true)
            .padding(12)
            .background(Color(red: 0.09, green: 0.11, blue: 0.15))
            .cornerRadius(12)
    }

    // MARK: - 逻辑

    private var canSign: Bool {
        ipaURL != nil && p12URL != nil && mpURL != nil
    }

    private func startSign() {
        guard let ipa = ipaURL, let p12 = p12URL, let mp = mpURL else { return }
        signing = true
        errorText = nil
        resultURL = nil
        installURL = nil
        log = ""

        let out = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("signed-\(Int(Date().timeIntervalSince1970)).ipa")

        DispatchQueue.global(qos: .userInitiated).async {
            let r = Signer.sign(ipa: ipa, p12: p12, password: password, profile: mp,
                                output: out,
                                bundleId: bundleId.isEmpty ? nil : bundleId,
                                displayName: displayName.isEmpty ? nil : displayName,
                                version: version.isEmpty ? nil : version) { line in
                DispatchQueue.main.async { log += line + "\n" }
            }
            DispatchQueue.main.async {
                signing = false
                if r.ok, let url = r.outputURL {
                    resultURL = url
                    // 起本地服务，准备 OTA 安装
                    let (manifest, portReady) = buildManifest(for: url)
                    if portReady {
                        try? server.start(ipa: url, manifestXML: manifest)
                        installURL = "itms-services://?action=download-manifest&url=http://127.0.0.1:\(server.port)/manifest.plist"
                    }
                    openInstall(installURL)
                } else {
                    errorText = "签名失败，看日志"
                }
            }
        }
    }

    private func buildManifest(for url: URL) -> (String, Bool) {
        let name = url.deletingPathExtension().lastPathComponent
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>items</key><array><dict>
        <key>assets</key><array><dict><key>kind</key><string>software-package</string>
        <key>url</key><string>http://127.0.0.1:PORT/app.ipa</string></dict></array>
        <key>metadata</key><dict><key>bundle-identifier</key><string>\(bundleId.isEmpty ? "com.unknown.app" : bundleId)</string>
        <key>kind</key><string>software</string><key>title</key><string>\(name)</string></dict>
        </dict></array></dict></plist>
        """
        return (xml, true)
    }

    private func openInstall(_ url: String?) {
        guard let url, let u = URL(string: url) else { return }
        UIApplication.shared.open(u, options: [:], completionHandler: nil)
    }

    private func byteText(_ url: URL) -> String {
        let n = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        return ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }
}
