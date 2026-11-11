import Foundation
import UIKit
import Network

/// 本地 OTA 安装：起一个临时 HTTP 服务，把 manifest.plist 和 ipa 暴露出去，
/// 然后打开 itms-services:// 触发系统安装。装完自动停。
enum Installer {

    private static var server: LocalServer?
    private static var bgTask: UIBackgroundTaskIdentifier = .invalid

    static func install(ipa: URL, bundleId: String) {
        // 保活：安装期间别让 App 被挂起
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "ota-install") {
            endBackground()
        }

        let sv = LocalServer()
        let manifest = makeManifest(ipaName: ipa.lastPathComponent, bundleId: bundleId)
        guard let port = try? sv.start(file: ipa, manifestXML: manifest) else {
            endBackground()
            return
        }
        server = sv

        guard let url = URL(string: "itms-services://?action=download-manifest&url=http://127.0.0.1:\(port)/manifest.plist") else {
            endBackground()
            return
        }
        UIApplication.shared.open(url, options: [:]) { _ in }

        // 给系统 90 秒下载时间，然后收摊
        DispatchQueue.main.asyncAfter(deadline: .now() + 90) {
            endBackground()
        }
    }

    private static func endBackground() {
        server?.stop()
        server = nil
        if bgTask != .invalid {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
    }

    private static func makeManifest(ipaName: String, bundleId: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>items</key><array><dict>
        <key>assets</key><array><dict>
        <key>kind</key><string>software-package</string>
        <key>url</key><string>http://127.0.0.1:PORT/app.ipa</string>
        </dict></array>
        <key>metadata</key><dict>
        <key>bundle-identifier</key><string>\(bundleId)</string>
        <key>bundle-version</key><string>1</string>
        <key>kind</key><string>software</string>
        <key>title</key><string>\(ipaName)</string>
        </dict></dict></array></dict></plist>
        """
    }
}

// MARK: - 本地 HTTP 服务

final class LocalServer {
    private var listener: NWListener?
    private var ipa: URL?
    private var manifest: String?

    func start(file: URL, manifestXML: String) throws -> UInt16 {
        stop()
        ipa = file
        manifest = manifestXML

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let l = try NWListener(using: params, on: .any)
        listener = l

        let sem = DispatchSemaphore(value: 0)
        var bound: UInt16 = 0

        l.stateUpdateHandler = { state in
            if case .ready = state, let p = l.port?.rawValue {
                bound = p
                sem.signal()
            } else if case .failed = state {
                sem.signal()
            }
        }
        l.newConnectionHandler = { [weak self] conn in
            self?.handle(conn)
        }
        l.start(queue: .global(qos: .userInitiated))
        _ = sem.wait(timeout: .now() + 3)
        guard bound > 0 else { throw NSError(domain: "LocalServer", code: 1) }
        return bound
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: .global(qos: .userInitiated))
        read(conn, Data())
    }

    private func read(_ conn: NWConnection, _ buf: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, err in
            guard let self else { conn.cancel(); return }
            var b = buf
            if let data { b.append(data) }
            if let r = b.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(data: b[..<r.lowerBound], encoding: .utf8) ?? ""
                let path = head.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
                self.respond(conn, path: path)
            } else if done || err != nil {
                conn.cancel()
            } else {
                self.read(conn, b)
            }
        }
    }

    private func respond(_ conn: NWConnection, path: String) {
        var body = Data()
        var ctype = "application/octet-stream"
        var status = "200 OK"

        if path.hasPrefix("/manifest") {
            body = Data((manifest ?? "").utf8)
            ctype = "application/xml; charset=utf-8"
        } else if path.hasPrefix("/app.ipa") {
            if let ipa, let d = try? Data(contentsOf: ipa) { body = d }
            else { status = "404 Not Found" }
        } else {
            status = "404 Not Found"
            body = Data("not found".utf8)
            ctype = "text/plain"
        }

        var head = "HTTP/1.1 \(status)\r\n"
        head += "Content-Type: \(ctype)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n\r\n"
        var out = Data(head.utf8)
        out.append(body)
        conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
    }
}
