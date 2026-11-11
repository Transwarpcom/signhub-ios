import Foundation
import Network

/// 极简本地 HTTP 服务：只服务 /manifest.plist 和 /app.ipa，
/// 供系统 itms-services 安装流程取包。
final class LocalServer {

    private var listener: NWListener?
    private(set) var port: UInt16 = 0
    private var manifestData: Data?
    private var ipaURL: URL?
    private var manifestName = "manifest.plist"

    var isRunning: Bool { listener != nil }

    func start(ipa: URL, manifestXML: String) throws {
        stop()
        guard let nwPort = NWEndpoint.Port(rawValue: 0) else { throw NSError(domain: "port", code: 0) }

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let l = try NWListener(using: params, on: nwPort)
        self.ipaURL = ipa
        self.manifestData = manifestXML.data(using: .utf8)
        self.manifestName = "manifest.plist"

        l.stateUpdateHandler = { [weak self] state in
            if case .ready = state, let p = l.port?.rawValue {
                self?.port = p
            }
        }
        l.newConnectionHandler = { [weak self] conn in
            self?.handle(conn)
        }
        l.start(queue: .global(qos: .userInitiated))
        self.listener = l

        // 等端口就绪
        let deadline = Date().addingTimeInterval(3)
        while port == 0 && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        port = 0
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: .global(qos: .userInitiated))
        readRequest(conn, buffer: Data())
    }

    private func readRequest(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isDone, error in
            guard let self else { conn.cancel(); return }
            var buf = buffer
            if let data { buf.append(data) }

            if let headerEnd = buf.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(data: buf[..<headerEnd.lowerBound], encoding: .utf8) ?? ""
                let path = head.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
                self.respond(conn, path: path)
                return
            }
            if isDone || error != nil || buf.count > 1 << 20 {
                conn.cancel()
                return
            }
            self.readRequest(conn, buffer: buf)
        }
    }

    private func respond(_ conn: NWConnection, path: String) {
        var body = Data()
        var contentType = "application/octet-stream"
        var status = "200 OK"

        if path.hasPrefix("/manifest") {
            body = manifestData ?? Data()
            contentType = "application/xml"
        } else if path.hasPrefix("/app") {
            if let url = ipaURL, let d = try? Data(contentsOf: url) {
                body = d
                contentType = "application/octet-stream"
            } else {
                status = "404 Not Found"
            }
        } else {
            status = "404 Not Found"
            body = Data("not found".utf8)
            contentType = "text/plain"
        }

        var resp = "HTTP/1.1 \(status)\r\n"
        resp += "Content-Type: \(contentType)\r\n"
        resp += "Content-Length: \(body.count)\r\n"
        resp += "Connection: close\r\n\r\n"
        var out = Data(resp.utf8)
        out.append(body)

        conn.send(content: out, completion: .contentProcessed { _ in
            conn.cancel()
        })
    }
}
