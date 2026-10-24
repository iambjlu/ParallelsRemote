import Foundation
import Network

struct HTTPRequest {
    var method: String
    var path: String
    var query: [String: String]
    var headers: [String: String]   // key 皆為小寫
    var body: Data
    var remote: String = ""         // 來源位址(用於登入失敗鎖定)
    var secure: Bool = false        // 是否為 HTTPS 連線

    /// 讀取指定名稱的 Cookie
    func cookie(_ name: String) -> String? {
        for part in (headers["cookie"] ?? "").split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if kv.count == 2, kv[0] == name { return kv[1] }
        }
        return nil
    }

    func json() -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
    }
}

struct HTTPResponse {
    var status: Int = 200
    var contentType: String = "application/json; charset=utf-8"
    var body: Data = Data()
    var headers: [String: String] = [:]   // 額外標頭(例如 Set-Cookie)

    static func json(_ obj: Any, status: Int = 200) -> HTTPResponse {
        let d = (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])) ?? Data("{}".utf8)
        return HTTPResponse(status: status, body: d)
    }
    static func error(_ status: Int, _ msg: String) -> HTTPResponse { .json(["error": msg], status: status) }
    static func html(_ s: String) -> HTTPResponse {
        HTTPResponse(contentType: "text/html; charset=utf-8", body: Data(s.utf8))
    }
}

/// 極簡 HTTP/1.1 伺服器(Network.framework,每個連線只處理一個請求)。
/// 僅接受來自區網、Tailscale 與本機的連線。
final class HTTPServer: @unchecked Sendable {
    /// 對外監聽的埠。HTTP 模式下直接服務;HTTPS 模式下是「前門」,依第一個位元組分流。
    private let listener: NWListener
    /// HTTPS 模式專用:只綁在本機的 TLS 服務(前門把 TLS 連線轉給它)
    private let inner: NWListener?
    private let handler: @Sendable (HTTPRequest) async -> HTTPResponse
    private let queue = DispatchQueue(label: "http.server")
    private let maxBody = 64 * 1024
    private let secure: Bool
    private var innerPort: UInt16 = 0
    /// 內部連線的本機埠 -> 真正的遠端位址(經前門轉送後,內部服務看到的來源都是 127.0.0.1)
    private var realRemote: [UInt16: String] = [:]
    private let mapLock = NSLock()

    /// identity 不為 nil 時以 TLS(HTTPS)提供服務,同埠收到明文 HTTP 會轉址到 https://。
    init(port: UInt16, identity: SecIdentity? = nil, handler: @escaping @Sendable (HTTPRequest) async -> HTTPResponse) throws {
        guard let p = NWEndpoint.Port(rawValue: port) else { throw ShellError(message: "無效的埠") }
        if let identity, let secId = sec_identity_create(identity) {
            let tls = NWProtocolTLS.Options()
            sec_protocol_options_set_local_identity(tls.securityProtocolOptions, secId)
            sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
            let params = NWParameters(tls: tls)
            params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)   // 只綁本機
            inner = try NWListener(using: params)
            listener = try NWListener(using: .tcp, on: p)
        } else {
            inner = nil
            listener = try NWListener(using: .tcp, on: p)
        }
        secure = inner != nil
        self.handler = handler
    }

    func start(onState: @escaping @Sendable (NWListener.State) -> Void) {
        guard let inner else {
            listener.stateUpdateHandler = onState
            listener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
            listener.start(queue: queue)
            return
        }
        // HTTPS:先啟動本機 TLS 服務,拿到它的埠之後才開前門
        inner.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        inner.stateUpdateHandler = { [weak self] st in
            guard let self else { return }
            switch st {
            case .ready:
                self.innerPort = inner.port?.rawValue ?? 0
                self.listener.stateUpdateHandler = onState
                self.listener.newConnectionHandler = { [weak self] conn in self?.acceptFront(conn) }
                self.listener.start(queue: self.queue)
            case .failed: onState(st)
            default: break
            }
        }
        inner.start(queue: queue)
    }

    func stop() { listener.cancel(); inner?.cancel() }

    // MARK: 前門(HTTPS 模式):TLS 轉給內部服務,明文 HTTP 轉址到 https://

    private func acceptFront(_ conn: NWConnection) {
        guard Self.isAllowed(conn.endpoint) else { conn.cancel(); return }
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, _, err in
            guard let self, err == nil, let data, !data.isEmpty else { conn.cancel(); return }
            if data[data.startIndex] == 0x16 { self.proxy(conn, first: data) }   // TLS ClientHello
            else { self.redirect(conn, buffer: data) }
        }
    }

    private func proxy(_ client: NWConnection, first: Data) {
        guard innerPort != 0, let port = NWEndpoint.Port(rawValue: innerPort) else { client.cancel(); return }
        let out = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
        let real = Self.remoteAddress(client.endpoint)
        var key: UInt16?
        out.stateUpdateHandler = { [weak self] st in
            guard let self else { return }
            switch st {
            case .ready:
                if case .hostPort(_, let lp)? = out.currentPath?.localEndpoint {
                    key = lp.rawValue
                    self.mapLock.withLock { self.realRemote[lp.rawValue] = real }
                }
                out.send(content: first, completion: .contentProcessed { _ in
                    Self.pipe(client, out); Self.pipe(out, client)
                })
            case .failed, .cancelled:
                if let key { self.mapLock.withLock { self.realRemote[key] = nil } }
                client.cancel()
            default: break
            }
        }
        out.start(queue: queue)
    }

    /// 單向搬運資料,任一邊結束就把兩邊都關掉
    private static func pipe(_ a: NWConnection, _ b: NWConnection) {
        a.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, done, err in
            if let data, !data.isEmpty {
                b.send(content: data, completion: .contentProcessed { e in
                    if e == nil { pipe(a, b) } else { a.cancel(); b.cancel() }
                })
            } else if done || err != nil { a.cancel(); b.cancel() }
        }
    }

    private func redirect(_ conn: NWConnection, buffer: Data) {
        // 讀到標頭結束,取出 Host 與路徑
        guard let sep = buffer.range(of: Data("\r\n\r\n".utf8)) else {
            guard buffer.count < 8192 else { conn.cancel(); return }
            conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] d, _, _, e in
                guard let self, e == nil, let d else { conn.cancel(); return }
                self.redirect(conn, buffer: buffer + d)
            }
            return
        }
        let lines = String(decoding: buffer[buffer.startIndex..<sep.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
        let first = lines[0].split(separator: " ")
        let host = lines.dropFirst().compactMap { l -> String? in
            guard let i = l.firstIndex(of: ":"), l[..<i].lowercased() == "host" else { return nil }
            return l[l.index(after: i)...].trimmingCharacters(in: .whitespaces)
        }.first
        guard first.count >= 2, let host, !host.isEmpty, !host.contains("/"), !host.contains(" ") else {
            send(conn, .error(400, "無效的請求")); return
        }
        // 302/307 是暫時轉址,瀏覽器不會永久快取;之後關掉 HTTPS 也不會打不開
        let status = (first[0] == "GET" || first[0] == "HEAD") ? 302 : 307
        let head = "HTTP/1.1 \(status) \(status == 302 ? "Found" : "Temporary Redirect")\r\nLocation: https://\(host)\(first[1])\r\n" +
                   "Content-Length: 0\r\nConnection: close\r\n\r\n"
        conn.send(content: Data(head.utf8), completion: .contentProcessed { _ in conn.cancel() })
    }

    // MARK: 連線

    private func accept(_ conn: NWConnection) {
        guard Self.isAllowed(conn.endpoint) else { conn.cancel(); return }
        conn.start(queue: queue)
        receive(conn, buffer: Data())
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, done, err in
            guard let self else { return }
            var buf = buffer
            if let data { buf.append(data) }
            if err != nil || (done && data == nil) { conn.cancel(); return }
            if buf.count > self.maxBody + 16 * 1024 { self.send(conn, .error(413, "請求過大")); return }

            switch Self.parse(buf) {
            case .incomplete:
                self.receive(conn, buffer: buf)
            case .bad:
                self.send(conn, .error(400, "無效的請求"))
            case .request(var req, let need):
                if req.body.count < need { self.receive(conn, buffer: buf); return }
                req.remote = self.realAddress(conn.endpoint)
                req.secure = self.secure
                Task {
                    let res = await self.handler(req)
                    self.send(conn, res)
                }
            }
        }
    }

    private func send(_ conn: NWConnection, _ r: HTTPResponse) {
        let reason = [200: "OK", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found",
                      409: "Conflict", 429: "Too Many Requests", 413: "Payload Too Large", 500: "Internal Server Error"][r.status] ?? "OK"
        var head = "HTTP/1.1 \(r.status) \(reason)\r\n"
        head += "Content-Type: \(r.contentType)\r\nContent-Length: \(r.body.count)\r\n"
        head += "Cache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n"
        for (k, v) in r.headers { head += "\(k): \(v)\r\n" }
        head += "\r\n"
        conn.send(content: Data(head.utf8) + r.body, completion: .contentProcessed { _ in conn.cancel() })
    }

    // MARK: 解析

    private enum Parsed { case incomplete, bad, request(HTTPRequest, bodyLength: Int) }

    private static func parse(_ data: Data) -> Parsed {
        guard let sep = data.range(of: Data("\r\n\r\n".utf8)) else { return .incomplete }
        let head = String(decoding: data[data.startIndex..<sep.lowerBound], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        let first = lines.removeFirst().split(separator: " ")
        guard first.count >= 2 else { return .bad }
        var headers: [String: String] = [:]
        for l in lines {
            guard let i = l.firstIndex(of: ":") else { continue }
            headers[l[..<i].lowercased()] = l[l.index(after: i)...].trimmingCharacters(in: .whitespaces)
        }
        let target = String(first[1])
        let parts = target.split(separator: "?", maxSplits: 1)
        var q: [String: String] = [:]
        if parts.count == 2 {
            for kv in parts[1].split(separator: "&") {
                let p = kv.split(separator: "=", maxSplits: 1)
                q[String(p[0]).removingPercentEncoding ?? ""] = p.count > 1 ? (String(p[1]).removingPercentEncoding ?? "") : ""
            }
        }
        let need = Int(headers["content-length"] ?? "0") ?? 0
        let body = Data(data[sep.upperBound...])
        let path = String(parts.first ?? "/").removingPercentEncoding ?? "/"
        return .request(HTTPRequest(method: String(first[0]), path: path, query: q, headers: headers, body: body), bodyLength: need)
    }

    private func realAddress(_ ep: NWEndpoint) -> String {
        if case .hostPort(_, let port) = ep, let real = mapLock.withLock({ realRemote[port.rawValue] }) { return real }
        return Self.remoteAddress(ep)
    }

    private static func remoteAddress(_ ep: NWEndpoint) -> String {
        guard case .hostPort(let host, _) = ep else { return "" }
        return "\(host)".split(separator: "%").first.map(String.init) ?? ""
    }

    // MARK: 來源限制

    static func isAllowed(_ ep: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = ep else { return false }
        switch host {
        case .ipv4(let a): return allowedV4(Array(a.rawValue))
        case .ipv6(let a):
            let b = Array(a.rawValue)
            if b == [UInt8](repeating: 0, count: 15) + [1] { return true }                       // ::1
            if b[0] == 0xfd { return true }                                                      // ULA(含 Tailscale fd7a:)
            if b[0] == 0xfe && (b[1] & 0xc0) == 0x80 { return true }                             // link-local
            if b[0..<10].allSatisfy({ $0 == 0 }) && b[10] == 0xff && b[11] == 0xff { return allowedV4(Array(b[12...])) }
            return false
        default: return false
        }
    }

    private static func allowedV4(_ b: [UInt8]) -> Bool {
        guard b.count == 4 else { return false }
        switch (b[0], b[1]) {
        case (10, _), (127, _), (192, 168): return true
        case (172, 16...31): return true
        case (100, 64...127): return true     // CGNAT,Tailscale 使用
        default: return false
        }
    }
}
