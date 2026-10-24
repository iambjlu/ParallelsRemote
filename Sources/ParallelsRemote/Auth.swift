import Foundation
import CryptoKit
import CommonCrypto
import Security

/// 登入密碼(在 Mac 端的設定視窗設定)與網頁登入 session。
/// 密碼以 PBKDF2-HMAC-SHA256 加鹽雜湊後存檔;session 只存 token 的 SHA-256,不存明文。
final class Auth: @unchecked Sendable {
    private struct Stored: Codable {
        var passwordHash: String?
        var sessions: [String: Date] = [:]   // sha256(token) -> 到期時間
    }

    private let lock = NSLock()
    private var stored: Stored
    private var failures: [String: (count: Int, until: Date)] = [:]
    private let url = Config.directory.appendingPathComponent("auth.json")
    static let sessionLifetime: TimeInterval = 30 * 24 * 3600

    init() {
        if let d = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(Stored.self, from: d) { stored = s }
        else { stored = Stored() }
        prune()
    }

    /// 是否已設定密碼;設定後所有 API 都要求登入。
    var isRequired: Bool { lock.withLock { stored.passwordHash != nil } }
    var hasPassword: Bool { isRequired }

    // MARK: 密碼

    func setPassword(_ pw: String) {
        lock.withLock {
            stored.passwordHash = Self.hash(pw)
            stored.sessions = [:]          // 換密碼 = 所有已登入的裝置都要重新登入
            save()
        }
    }

    func clearPassword() {
        lock.withLock { stored.passwordHash = nil; stored.sessions = [:]; save() }
    }

    enum LoginResult { case ok(token: String), wrong, locked(seconds: Int) }

    /// 驗證密碼;連續錯 5 次就鎖該來源位址 60 秒,避免暴力破解。
    func login(password: String, from remote: String) -> LoginResult {
        lock.withLock {
            if let f = failures[remote], f.until > Date() { return .locked(seconds: Int(f.until.timeIntervalSinceNow) + 1) }
            guard let h = stored.passwordHash, Self.verify(password, h) else {
                let n = (failures[remote]?.count ?? 0) + 1
                // 第 5 次錯誤就鎖 60 秒並重新計數;未達 5 次時 until 設在過去(不鎖)
                failures[remote] = n >= 5 ? (0, Date().addingTimeInterval(60)) : (n, .distantPast)
                return .wrong
            }
            failures[remote] = nil
            let token = Self.randomToken()
            stored.sessions[Self.sha(token)] = Date().addingTimeInterval(Self.sessionLifetime)
            prune(); save()
            return .ok(token: token)
        }
    }

    func validate(token: String?) -> Bool {
        guard let token, !token.isEmpty else { return false }
        return lock.withLock {
            guard let exp = stored.sessions[Self.sha(token)] else { return false }
            return exp > Date()
        }
    }

    func logout(token: String?) {
        guard let token else { return }
        lock.withLock { stored.sessions[Self.sha(token)] = nil; save() }
    }

    // MARK: 內部

    private func prune() { stored.sessions = stored.sessions.filter { $0.value > Date() } }

    private func save() {
        guard let d = try? JSONEncoder().encode(stored) else { return }
        try? d.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func randomToken() -> String {
        var b = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, b.count, &b)
        return b.map { String(format: "%02x", $0) }.joined()
    }

    private static func sha(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: PBKDF2

    private static func pbkdf2(_ pw: String, salt: Data, iterations: Int) -> Data {
        var out = Data(count: 32)
        let pwBytes = Array(pw.utf8)
        _ = out.withUnsafeMutableBytes { o in
            salt.withUnsafeBytes { s in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pwBytes.map { Int8(bitPattern: $0) }, pwBytes.count,
                                     s.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                     CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations),
                                     o.bindMemory(to: UInt8.self).baseAddress, 32)
            }
        }
        return out
    }

    static func hash(_ pw: String) -> String {
        var salt = Data(count: 16)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        let iters = 200_000
        return "pbkdf2$\(iters)$\(salt.base64EncodedString())$\(pbkdf2(pw, salt: salt, iterations: iters).base64EncodedString())"
    }

    static func verify(_ pw: String, _ stored: String) -> Bool {
        let p = stored.split(separator: "$").map(String.init)
        guard p.count == 4, p[0] == "pbkdf2", let iters = Int(p[1]),
              let salt = Data(base64Encoded: p[2]), let want = Data(base64Encoded: p[3]) else { return false }
        let got = pbkdf2(pw, salt: salt, iterations: iters)
        // 固定時間比較
        return got.count == want.count && zip(got, want).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
