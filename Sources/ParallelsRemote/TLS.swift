import Foundation
import Security

/// 自簽 HTTPS 憑證。瀏覽器會顯示憑證無效的警告(可略過);
/// 目的是讓密碼登入不以明文傳送,頁面也成為 secure context(Clipboard API 等需要)。
enum TLS {
    private static var dir: URL {
        let d = Config.directory.appendingPathComponent("tls", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private static let p12Password = "parallels-remote"

    /// 讀取(必要時產生)自簽憑證並回傳可給 Network.framework 用的 identity。
    /// hosts:要寫進憑證 SAN 的主機名稱與 IP。
    static func loadIdentity(hosts: [String], regenerate: Bool = false) async throws -> SecIdentity {
        let p12 = dir.appendingPathComponent("identity.p12")
        if regenerate || !FileManager.default.fileExists(atPath: p12.path) {
            try await generate(hosts: hosts)
        }
        return try identity(from: p12)
    }

    private static func generate(hosts: [String]) async throws {
        let key = dir.appendingPathComponent("key.pem"), cert = dir.appendingPathComponent("cert.pem")
        let cfg = dir.appendingPathComponent("openssl.cnf"), p12 = dir.appendingPathComponent("identity.p12")

        var alt: [String] = []
        var dnsN = 0, ipN = 0
        for h in Set(hosts).sorted() where !h.isEmpty {
            if h.range(of: #"^\d{1,3}(\.\d{1,3}){3}$"#, options: .regularExpression) != nil { ipN += 1; alt.append("IP.\(ipN) = \(h)") }
            else { dnsN += 1; alt.append("DNS.\(dnsN) = \(h)") }
        }
        let conf = """
        [req]
        distinguished_name = dn
        x509_extensions = v3
        prompt = no
        [dn]
        CN = Parallels Remote
        [v3]
        basicConstraints = CA:FALSE
        keyUsage = digitalSignature, keyEncipherment
        extendedKeyUsage = serverAuth
        subjectAltName = @alt
        [alt]
        \(alt.joined(separator: "\n"))
        """
        try conf.write(to: cfg, atomically: true, encoding: .utf8)

        // 有效期限 825 天(Apple 對受信任憑證的上限;這裡不受信任,但保持一致)
        try await Shell.check("/usr/bin/openssl", ["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "825",
                                                   "-keyout", key.path, "-out", cert.path, "-config", cfg.path])
        try await Shell.check("/usr/bin/openssl", ["pkcs12", "-export", "-inkey", key.path, "-in", cert.path,
                                                   "-out", p12.path, "-passout", "pass:\(p12Password)"])
        for f in [key, p12] { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: f.path) }
    }

    private static func identity(from p12: URL) throws -> SecIdentity {
        let data = try Data(contentsOf: p12)
        var items: CFArray?
        let opts: [String: Any] = [kSecImportExportPassphrase as String: p12Password,
                                   kSecImportToMemoryOnly as String: true]   // 不寫進鑰匙圈,免跳授權視窗
        let status = SecPKCS12Import(data as CFData, opts as CFDictionary, &items)
        guard status == errSecSuccess, let arr = items as? [[String: Any]],
              let first = arr.first, let id = first[kSecImportItemIdentity as String] else {
            throw ShellError(message: "匯入憑證失敗(OSStatus \(status))")
        }
        return id as! SecIdentity
    }
}
