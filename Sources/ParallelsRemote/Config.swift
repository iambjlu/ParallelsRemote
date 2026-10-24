import Foundation

struct Config: Codable {
    /// 是否以 HTTPS(自簽憑證)提供服務;同一個埠收到明文 HTTP 會轉址到 https://。
    var https: Bool? = false
    var port: UInt16 = 8888
    var networkName: String = "Shared"
    /// 副本 SSH 轉發的起始埠:第 N 個副本使用 base + N
    var sshBasePort: Int = 2200
    var guestSSHPort: Int = 22

    static var directory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ParallelsRemote", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    static var url: URL { directory.appendingPathComponent("config.json") }

    static func load() -> Config {
        if let d = try? Data(contentsOf: url), var c = try? JSONDecoder().decode(Config.self, from: d) {
            if c.port == 8787 { c.port = 8888; c.save() }   // 8787 是舊的預設值,不是使用者自己選的
            return c
        }
        let c = Config()
        c.save()
        return c
    }

    func save() {
        guard let d = try? JSONEncoder().encode(self) else { return }
        try? d.write(to: Self.url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.url.path)
    }
}
