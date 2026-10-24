import Foundation

struct Router: Sendable {
    let prl: Parallels
    let auth: Auth
    static let cookieName = "pr_session"

    func handle(_ req: HTTPRequest) async -> HTTPResponse {
        if req.method == "GET" && (req.path == "/" || req.path == "/index.html") { return .html(webPage) }
        if req.method == "GET", let asset = Self.pwaAsset(req.path) { return asset }   // PWA 靜態資源(不含機敏資料)
        guard req.path.hasPrefix("/api/") else { return .error(404, "Not Found") }

        // 不需要登入的端點:查詢登入狀態、登入、登出
        switch (req.method, req.path) {
        case ("GET", "/api/session"):
            return .json(["authRequired": auth.isRequired,
                          "authed": !auth.isRequired || auth.validate(token: req.cookie(Self.cookieName))])
        case ("POST", "/api/login"): return login(req)
        case ("POST", "/api/logout"):
            auth.logout(token: req.cookie(Self.cookieName))
            var r = HTTPResponse.json(["ok": true])
            r.headers["Set-Cookie"] = Self.cookie("", maxAge: 0, secure: req.secure)
            return r
        default: break
        }

        // 其餘 API:密碼已設定就必須有有效的登入 session
        if auth.isRequired, !auth.validate(token: req.cookie(Self.cookieName)) { return .error(401, "需要登入") }

        do { return try await route(req) }
        catch let e as APIError { return .error(e.status, e.message) }
        catch { return .error(500, "\(error)") }
    }

    private static func pwaAsset(_ path: String) -> HTTPResponse? {
        switch path {
        case "/manifest.webmanifest":
            return HTTPResponse(contentType: "application/manifest+json; charset=utf-8", body: Data(PWA.manifest.utf8))
        case "/sw.js":
            return HTTPResponse(contentType: "text/javascript; charset=utf-8", body: Data(PWA.serviceWorker.utf8),
                                headers: ["Service-Worker-Allowed": "/"])
        case "/icon-192.png": return HTTPResponse(contentType: "image/png", body: PWA.icon192)
        case "/icon-512.png": return HTTPResponse(contentType: "image/png", body: PWA.icon512)
        case "/icon-maskable-512.png": return HTTPResponse(contentType: "image/png", body: PWA.iconMaskable512)
        default: return nil
        }
    }

    private func login(_ req: HTTPRequest) -> HTTPResponse {
        guard auth.isRequired else { return .json(["ok": true]) }
        switch auth.login(password: req.json()["password"] as? String ?? "", from: req.remote) {
        case .ok(let token):
            var r = HTTPResponse.json(["ok": true])
            r.headers["Set-Cookie"] = Self.cookie(token, maxAge: Int(Auth.sessionLifetime), secure: req.secure)
            return r
        case .wrong: return .error(401, "密碼錯誤")
        case .locked(let s): return .error(429, "錯誤次數過多,請 \(s) 秒後再試")
        }
    }

    /// HttpOnly:網頁 JavaScript 讀不到;SameSite=Strict:擋跨站請求;HTTPS 連線時加 Secure。
    private static func cookie(_ value: String, maxAge: Int, secure: Bool) -> String {
        "\(cookieName)=\(value); Path=/; Max-Age=\(maxAge); HttpOnly; SameSite=Strict" + (secure ? "; Secure" : "")
    }

    private func route(_ req: HTTPRequest) async throws -> HTTPResponse {
        let seg = req.path.split(separator: "/").map(String.init)   // ["api", ...]
        let m = req.method
        let body = req.json()

        let p = Array(seg.dropFirst())
        let ok = HTTPResponse.json(["ok": true])

        if m == "GET", p == ["state"] {
            async let vms = prl.listVMs()
            async let fw = prl.forwards()
            let forwards = try await fw.map { f -> [String: Any] in
                ["proto": f.proto, "name": f.name ?? NSNull(), "sourcePort": f.sourcePort,
                 "target": f.target, "destPort": f.destPort, "managed": f.managed]
            }
            return .json(["vms": try await vms, "forwards": forwards,
                          "host": ["cpus": Parallels.hostCPUs, "memMB": Parallels.hostMemMB]])
        }

        if p.count == 2, p[0] == "vm", m == "DELETE" {
            try await prl.deleteVM(id: p[1], confirmName: body["confirmName"] as? String ?? ""); return ok
        }

        if p.first == "vm", p.count >= 3 {
            let id = p[1]
            if p.count == 3, m == "POST", p[2] == "clone" {
                let r = try await prl.cloneVM(id: id, start: body["start"] as? Bool ?? false, name: body["name"] as? String)
                return .json(["id": r.id, "name": r.name, "sshPort": r.sshPort, "warnings": r.warnings])
            }
            if p.count == 3, m == "POST", p[2] == "revert" {
                let name = try await prl.revertToLastSnapshot(id: id)
                return .json(["ok": true, "snapshot": name])
            }
            if p.count == 5, m == "POST", p[2] == "nic", p[4] == "connect" || p[4] == "disconnect" {
                try await prl.setNIC(id: id, nic: p[3], connect: p[4] == "connect"); return ok
            }
            if p.count == 3, m == "POST", p[2] == "spec" {
                try await prl.setSpec(id: id, cpus: body["cpus"] as? Int ?? 0, memMB: body["memMB"] as? Int ?? 0); return ok
            }
            if p.count == 3, m == "POST", p[2] != "snapshots" {
                try await prl.action(id: id, action: p[2]); return ok
            }
            if p[2] == "snapshots" {
                if p.count == 3, m == "GET" { return .json(["snapshots": try await prl.snapshots(id: id)]) }
                if p.count == 3, m == "POST" {
                    try await prl.createSnapshot(id: id, name: body["name"] as? String ?? ""); return ok
                }
                if p.count == 5, m == "POST", p[4] == "switch" {
                    try await prl.switchSnapshot(id: id, snapshot: p[3]); return ok
                }
                if p.count == 4, m == "DELETE" {
                    try await prl.deleteSnapshot(id: id, snapshot: p[3]); return ok
                }
            }
        }

        if p == ["forwards"], m == "POST" {
            let name = try await prl.addForward(
                proto: body["proto"] as? String ?? "tcp",
                sourcePort: body["sourcePort"] as? Int ?? 0,
                target: body["target"] as? String ?? "",
                destPort: body["destPort"] as? Int ?? 0)
            return .json(["ok": true, "name": name])
        }
        if p.count == 2, p[0] == "forwards", m == "DELETE" {
            try await prl.deleteForward(name: p[1]); return ok
        }

        return .error(404, "Not Found")
    }

    static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        return zip(x, y).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
