import Foundation

let prlctl = "/usr/local/bin/prlctl"
let prlsrvctl = "/usr/local/bin/prlsrvctl"

struct APIError: Error {
    let status: Int
    let message: String
}

/// 所有會改動狀態的操作都經過這個 actor 序列化,避免埠分配等競爭。
actor Parallels {
    var config: Config

    init(config: Config) { self.config = config }

    func update(_ c: Config) { config = c }

    // MARK: 驗證

    static func isUUID(_ s: String) -> Bool {
        s.range(of: #"^\{?[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\}?$"#,
                options: .regularExpression) != nil
    }

    private func requireID(_ s: String) throws -> String {
        guard Self.isUUID(s) else { throw APIError(status: 400, message: "無效的 ID") }
        return s
    }

    private func requireName(_ s: String) throws -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.count <= 80, !t.hasPrefix("-") else { throw APIError(status: 400, message: "無效的名稱") }
        return t
    }

    // MARK: VM

    func listVMs() async throws -> [[String: Any]] {
        let out = try await Shell.check(prlctl, ["list", "-a", "-f", "--json"])
        var vms = try JSONSerialization.jsonObject(with: Data(out.utf8)) as? [[String: Any]] ?? []

        // ip_configured 只會回報第一個 IP;多張網卡要從 `list -i` 取得全部 IPv4 與網卡清單,
        // 再依所屬的虛擬網路網段標示 IP 是 Shared、Host-Only 還是 Bridged。
        // 同一次查詢也取得 CPU / 記憶體規格,所以所有狀態的機器都要查。
        let all = Array(vms.enumerated())
        if !all.isEmpty {
            let subnets = await networkSubnets()
            let infos = await withTaskGroup(of: (Int, GuestInfo).self) { group -> [Int: GuestInfo] in
                for (i, v) in all {
                    guard let id = v["uuid"] as? String else { continue }
                    group.addTask { (i, await Self.guestInfo(id: id)) }
                }
                var r: [Int: GuestInfo] = [:]
                for await (i, info) in group { r[i] = info }
                return r
            }
            for (i, info) in infos {
                if info.cpus > 0 { vms[i]["hw"] = ["cpus": info.cpus, "memMB": info.memMB] }
                guard (vms[i]["status"] as? String) == "running" else { continue }
                // 某種網路的網卡全部被拔掉時,Parallels 仍會殘留舊 IP,這裡把它濾掉
                let kinds = Set(info.nics.map { Self.kind($0.type) })
                let dead = kinds.filter { k in info.nics.filter { Self.kind($0.type) == k }.allSatisfy { !$0.connected } }
                let ips = info.ips.map { ["ip": $0, "net": Self.label(for: $0, in: subnets)] }.filter { !dead.contains($0["net"] ?? "") }
                if !ips.isEmpty { vms[i]["ips"] = ips }
                vms[i]["nics"] = info.nics.map { n -> [String: Any] in
                    ["name": n.name, "kind": Self.kind(n.type), "mac": n.mac, "connected": n.connected]
                }
            }
        }
        return vms
    }

    private struct Subnet { let label: String; let base: UInt32; let mask: UInt32 }

    private static func ipv4Value(_ s: String) -> UInt32? {
        let p = s.split(separator: ".").compactMap { UInt32($0) }
        guard p.count == 4, p.allSatisfy({ $0 < 256 }) else { return nil }
        return p[0] << 24 | p[1] << 16 | p[2] << 8 | p[3]
    }

    /// Shared 與 Host-Only 虛擬網路的 IPv4 網段;不在這兩個網段內的就視為 Bridged。
    private func networkSubnets() async -> [Subnet] {
        var result: [Subnet] = []
        for (id, label) in [(config.networkName, "Shared"), ("Host-Only", "Host-Only")] {
            guard let out = try? await Shell.check(prlsrvctl, ["net", "info", id, "--json"]),
                  let d = (try? JSONSerialization.jsonObject(with: Data(out.utf8))) as? [String: Any],
                  let ad = d["Parallels adapter"] as? [String: Any],
                  let ip = ad["IPv4 address"] as? String, let mask = ad["IPv4 subnet mask"] as? String,
                  let ipv = Self.ipv4Value(ip), let mv = Self.ipv4Value(mask) else { continue }
            result.append(Subnet(label: label, base: ipv & mv, mask: mv))
        }
        return result
    }

    private static func label(for ip: String, in subnets: [Subnet]) -> String {
        guard let v = ipv4Value(ip) else { return "Bridged" }
        return subnets.first { v & $0.mask == $0.base }?.label ?? "Bridged"
    }

    private struct NICInfo: Sendable { let name: String; let type: String; let mac: String; let connected: Bool }
    private struct GuestInfo: Sendable { var ips: [String] = []; var nics: [NICInfo] = []; var cpus = 0; var memMB = 0 }

    private static func kind(_ type: String) -> String {
        switch type {
        case "shared": return "Shared"
        case "host-only": return "Host-Only"
        case "bridged": return "Bridged"
        default: return type.isEmpty ? "?" : type
        }
    }

    private static func guestInfo(id: String) async -> GuestInfo {
        guard let out = try? await Shell.check(prlctl, ["list", "-i", id, "--json"]),
              let first = ((try? JSONSerialization.jsonObject(with: Data(out.utf8))) as? [[String: Any]])?.first else { return GuestInfo() }
        var info = GuestInfo()
        if let addrs = (first["Network"] as? [String: Any])?["ipAddresses"] as? [[String: Any]] {
            info.ips = addrs.compactMap { ($0["type"] as? String) == "ipv4" ? $0["ip"] as? String : nil }
        }
        if let hw = first["Hardware"] as? [String: Any] {
            info.cpus = (hw["cpu"] as? [String: Any])?["cpus"] as? Int ?? 0
            // size 形如 "4096Mb"
            let size = ((hw["memory"] as? [String: Any])?["size"] as? String ?? "").lowercased()
            info.memMB = Int(size.trimmingCharacters(in: CharacterSet.decimalDigits.inverted)) ?? 0
            let names = hw.keys.filter { $0.range(of: #"^net\d+$"#, options: .regularExpression) != nil }
                .sorted { (Int($0.dropFirst(3)) ?? 0) < (Int($1.dropFirst(3)) ?? 0) }
            for n in names {
                guard let d = hw[n] as? [String: Any] else { continue }
                // 被拔掉的網卡會多一個 "state": "disconnected"
                info.nics.append(NICInfo(name: n, type: d["type"] as? String ?? "", mac: d["mac"] as? String ?? "",
                                         connected: (d["state"] as? String) != "disconnected"))
            }
        }
        return info
    }

    private func vm(_ id: String) async throws -> [String: Any] {
        let norm = id.trimmingCharacters(in: CharacterSet(charactersIn: "{}")).lowercased()
        guard let v = try await listVMs().first(where: {
            (($0["uuid"] as? String) ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "{}")).lowercased() == norm
        }) else { throw APIError(status: 404, message: "找不到 VM") }
        return v
    }

    func action(id: String, action: String) async throws {
        let id = try requireID(id)
        let args: [String]
        switch action {
        case "start": args = ["start", id]
        case "stop": args = ["stop", id]
        case "kill": args = ["stop", id, "--kill"]
        case "suspend": args = ["suspend", id]
        case "resume": args = ["resume", id]
        case "pause": args = ["pause", id]
        case "restart": args = ["restart", id]
        default: throw APIError(status: 400, message: "不支援的動作")
        }
        try await Shell.check(prlctl, args)
    }

    // MARK: 規格(CPU / 記憶體)

    static var hostCPUs: Int { ProcessInfo.processInfo.processorCount }
    static var hostMemMB: Int { Int(ProcessInfo.processInfo.physicalMemory / 1_048_576) }

    /// Parallels 只允許修改已關機的機器;記憶體以 MB 為單位。
    func setSpec(id: String, cpus: Int, memMB: Int) async throws {
        let id = try requireID(id)
        guard (1...Self.hostCPUs).contains(cpus) else { throw APIError(status: 400, message: "CPU 數量須介於 1 到 \(Self.hostCPUs)") }
        guard (256...Self.hostMemMB).contains(memMB) else { throw APIError(status: 400, message: "記憶體須介於 256 到 \(Self.hostMemMB) MB") }
        guard (try await vm(id)["status"] as? String) == "stopped" else { throw APIError(status: 409, message: "請先關機才能修改規格") }
        try await Shell.check(prlctl, ["set", id, "--cpus", String(cpus), "--memsize", String(memMB)])
    }

    // MARK: 快照

    func snapshots(id: String) async throws -> [[String: Any]] {
        let id = try requireID(id)
        let out = try await Shell.check(prlctl, ["snapshot-list", id, "--json"])
        guard let dict = try JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: [String: Any]] else { return [] }
        return dict.map { k, v in var v = v; v["id"] = k; return v }
            .sorted { ($0["date"] as? String ?? "") < ($1["date"] as? String ?? "") }
    }

    func createSnapshot(id: String, name: String) async throws {
        try await Shell.check(prlctl, ["snapshot", try requireID(id), "-n", try requireName(name)])
    }

    func switchSnapshot(id: String, snapshot: String) async throws {
        try await Shell.check(prlctl, ["snapshot-switch", try requireID(id), "-i", try requireID(snapshot)])
    }

    func deleteSnapshot(id: String, snapshot: String) async throws {
        try await Shell.check(prlctl, ["snapshot-delete", try requireID(id), "-i", try requireID(snapshot)])
    }

    /// 拔掉 / 連回網卡(僅能對執行中的機器操作,這是 Parallels 的限制)。
    func setNIC(id: String, nic: String, connect: Bool) async throws {
        let id = try requireID(id)
        guard nic.range(of: #"^net\d+$"#, options: .regularExpression) != nil else {
            throw APIError(status: 400, message: "無效的網卡名稱")
        }
        guard (try await vm(id)["status"] as? String) == "running" else {
            throw APIError(status: 409, message: "只有執行中的機器可以拔掉或連回網卡")
        }
        try await Shell.check(prlctl, ["set", id, connect ? "--device-connect" : "--device-disconnect", nic])
    }

    /// 回復到「最後一個快照」:優先用目前所在的快照(current),沒有的話用日期最新的。回傳快照名稱。
    func revertToLastSnapshot(id: String) async throws -> String {
        let list = try await snapshots(id: id)
        guard let target = list.first(where: { ($0["current"] as? Bool) == true }) ?? list.last,
              let sid = target["id"] as? String else {
            throw APIError(status: 404, message: "這台機器沒有快照")
        }
        try await switchSnapshot(id: id, snapshot: sid)
        return target["name"] as? String ?? ""
    }

    // MARK: 端口轉發

    struct Forward: Codable {
        var proto: String
        var name: String?
        var sourcePort: Int
        var target: String
        var destPort: Int
        var managed: Bool { name?.hasPrefix("pr-") ?? false }
    }

    func forwards() async throws -> [Forward] {
        let net = config.networkName
        let text = try await Shell.check(prlsrvctl, ["net", "info", net])
        // 規則名稱只存在於 JSON(未命名的規則 key 為空字串且會重複,所以只用來對照名稱)
        var names: [String: String] = [:]
        if let j = try? await Shell.check(prlsrvctl, ["net", "info", net, "--json"]),
           let root = try? JSONSerialization.jsonObject(with: Data(j.utf8)) as? [String: Any],
           let nat = root["NAT server"] as? [String: Any] {
            for (sect, proto) in [("TCP rules", "tcp"), ("UDP rules", "udp")] {
                for (k, v) in (nat[sect] as? [String: Any]) ?? [:] where !k.isEmpty {
                    if let r = v as? [String: Any], let sp = r["source port"] as? Int { names["\(proto)/\(sp)"] = k }
                }
            }
        }
        var result: [Forward] = []
        var proto = "tcp"
        let re = try NSRegularExpression(pattern: #"source port=(\d+) destination IP/VM id=(\S+) destination port=(\d+)"#)
        for line in text.split(separator: "\n") {
            let s = String(line)
            if s.contains("TCP rules") { proto = "tcp" }
            if s.contains("UDP rules") { proto = "udp" }
            if let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), m.numberOfRanges == 4,
               let a = Range(m.range(at: 1), in: s), let b = Range(m.range(at: 2), in: s), let c = Range(m.range(at: 3), in: s),
               let sp = Int(s[a]), let dp = Int(s[c]) {
                result.append(Forward(proto: proto, name: names["\(proto)/\(sp)"], sourcePort: sp, target: String(s[b]), destPort: dp))
            }
        }
        return result
    }

    func addForward(proto: String, sourcePort: Int, target: String, destPort: Int) async throws -> String {
        guard proto == "tcp" || proto == "udp" else { throw APIError(status: 400, message: "proto 必須是 tcp 或 udp") }
        guard (1...65535).contains(sourcePort), (1...65535).contains(destPort) else { throw APIError(status: 400, message: "埠號無效") }
        guard Int(config.port) != sourcePort else { throw APIError(status: 400, message: "不能佔用控制服務的埠") }
        let id = try requireID(target)
        if try await forwards().contains(where: { $0.proto == proto && $0.sourcePort == sourcePort }) {
            throw APIError(status: 409, message: "來源埠 \(sourcePort) 已被使用")
        }
        let name = "pr-\(proto)-\(sourcePort)"
        try await Shell.check(prlsrvctl, ["net", "set", config.networkName, "--nat-\(proto)-add", "\(name),\(sourcePort),\(id),\(destPort)"])
        return name
    }

    func deleteForward(name: String) async throws {
        guard name.range(of: #"^pr-(tcp|udp)-\d+$"#, options: .regularExpression) != nil else {
            throw APIError(status: 400, message: "只能刪除由本程式建立的規則(pr-*)")
        }
        let proto = name.hasPrefix("pr-tcp") ? "tcp" : "udp"
        try await Shell.check(prlsrvctl, ["net", "set", config.networkName, "--nat-\(proto)-del", name])
    }

    // MARK: 複製 / 刪除

    struct CopyResult: Codable {
        var id: String
        var name: String
        var sshPort: Int
        var warnings: [String]
    }

    private static func norm(_ id: String) -> String {
        id.trimmingCharacters(in: CharacterSet(charactersIn: "{}")).lowercased()
    }

    /// 以 APFS clone(cp -c)複製一台已關機的 VM,放在同一個資料夾(同磁區才能 clone)。
    func cloneVM(id: String, start: Bool, name: String? = nil) async throws -> CopyResult {
        let id = try requireID(id)
        let src = try await vm(id)
        guard let srcName = src["name"] as? String else { throw APIError(status: 500, message: "讀不到 VM 名稱") }
        let status = src["status"] as? String ?? ""
        guard ["stopped", "running", "suspended"].contains(status) else {
            throw APIError(status: 409, message: "\(srcName) 目前是 \(status) 狀態,請先恢復或關機再複製")
        }

        // 執行中的機器:先休眠(把記憶體寫進磁碟,檔案才一致)→ 複製 → 恢復原機。
        // 不論複製成功或失敗都要恢復,避免原機被留在休眠狀態。
        guard status == "running" else { return try await performClone(id: id, srcName: srcName, start: start, name: name) }
        try await Shell.check(prlctl, ["suspend", id])
        var result: CopyResult
        do {
            result = try await performClone(id: id, srcName: srcName, start: start, name: name)
        } catch {
            try? await Shell.check(prlctl, ["resume", id])
            throw error
        }
        do { try await Shell.check(prlctl, ["resume", id]) }
        catch { result.warnings.append("複製完成,但恢復原機失敗: \(error)") }
        return result
    }

    /// 使用者自訂的副本名稱會同時成為 VM 名稱與資料夾名稱,所以要擋掉路徑字元並確認沒有重名。
    private func resolveCloneName(_ requested: String?, fallback: String) async throws -> String {
        let t = (requested ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let name = t.isEmpty ? fallback : t
        guard name.count <= 80, !name.hasPrefix("."), !name.hasPrefix("-"),
              name.range(of: #"[/:\x00-\x1F]"#, options: .regularExpression) == nil else {
            throw APIError(status: 400, message: "名稱不能包含 / 或 :,不能以 . 或 - 開頭,最長 80 字")
        }
        if try await listVMs().contains(where: { ($0["name"] as? String) == name }) {
            throw APIError(status: 409, message: "已經有名為「\(name)」的機器")
        }
        return name
    }

    private func performClone(id: String, srcName: String, start: Bool, name requested: String?) async throws -> CopyResult {
        let info = try await Shell.check(prlctl, ["list", "-i", id, "--json"])
        guard let arr = try JSONSerialization.jsonObject(with: Data(info.utf8)) as? [[String: Any]],
              let home = arr.first?["Home"] as? String else { throw APIError(status: 500, message: "讀不到 VM 路徑") }
        let srcURL = URL(fileURLWithPath: home)
        let fmt = DateFormatter(); fmt.dateFormat = "yyMMdd-HHmmss"
        let name = try await resolveCloneName(requested, fallback: "\(srcName) copy \(fmt.string(from: Date()))")
        let dst = srcURL.deletingLastPathComponent().appendingPathComponent(name + srcURL.pathExtension.prefixed(with: "."))
        guard !FileManager.default.fileExists(atPath: dst.path) else { throw APIError(status: 409, message: "目的地已存在") }

        try await Shell.check("/bin/cp", ["-c", "-R", srcURL.path, dst.path])

        // 來源是休眠/執行中(已被休眠)時,副本會帶著記憶體狀態,Parallels 不允許修改休眠機器的設定(改不了 MAC)。
        // 副本是我們自己剛複製出來的,直接移除它的休眠狀態檔,等同於「斷電後開機」(磁碟為 crash-consistent)。
        // 只動副本資料夾,原機的狀態檔不受影響。
        if let files = try? FileManager.default.contentsOfDirectory(atPath: dst.path) {
            for f in files where f.hasSuffix(".mem") || f == "config.sav" || f == "suspended.png" {
                try? FileManager.default.removeItem(at: dst.appendingPathComponent(f))
            }
        }

        var warnings: [String] = []
        do {
            try await Shell.check(prlctl, ["register", dst.path, "--regenerate-src-uuid", "-n", name])
        } catch {
            try? FileManager.default.removeItem(at: dst)   // 註冊失敗就清掉剛複製的檔案
            throw error
        }
        guard let newVM = try await listVMs().first(where: { ($0["name"] as? String) == name }),
              let newID = newVM["uuid"] as? String else { throw APIError(status: 500, message: "註冊後找不到新 VM") }

        // 重新產生網卡 MAC,避免與來源衝突
        do {
            let info = try await Shell.check(prlctl, ["list", "-i", newID, "--json"])
            let hw = ((try? JSONSerialization.jsonObject(with: Data(info.utf8))) as? [[String: Any]])?.first?["Hardware"] as? [String: Any] ?? [:]
            let nics = hw.keys.filter { $0.range(of: #"^net\d+$"#, options: .regularExpression) != nil }.sorted()
            for nic in nics { try await Shell.check(prlctl, ["set", newID, "--device-set", nic, "--mac", "auto"]) }
        } catch { warnings.append("重設 MAC 失敗: \(error)") }

        // 分配 SSH 轉發埠
        let used = Set(try await forwards().map(\.sourcePort))
        var port = config.sshBasePort + 1
        while used.contains(port) { port += 1 }
        do { _ = try await addForward(proto: "tcp", sourcePort: port, target: newID, destPort: config.guestSSHPort) }
        catch { warnings.append("建立 SSH 轉發失敗: \(error)") }

        if start {
            do { try await Shell.check(prlctl, ["start", newID]) }
            catch { warnings.append("啟動失敗: \(error)") }
        }
        return CopyResult(id: newID, name: name, sshPort: port, warnings: warnings)
    }

    /// 永久刪除 VM(含檔案)。confirmName 必須與 VM 名稱完全相同,避免誤刪。
    func deleteVM(id: String, confirmName: String) async throws {
        let id = try requireID(id)
        let v = try await vm(id)
        let name = v["name"] as? String ?? ""
        guard !name.isEmpty, confirmName == name else { throw APIError(status: 403, message: "確認名稱不符,未刪除") }
        if (v["status"] as? String) != "stopped" {
            try await Shell.check(prlctl, ["stop", id, "--kill"])
        }
        let target = Self.norm(id)
        for f in try await forwards() where f.managed && Self.norm(f.target) == target {
            try? await deleteForward(name: f.name!)
        }
        try await Shell.check(prlctl, ["delete", id])
    }
}

private extension String {
    func prefixed(with p: String) -> String { isEmpty ? "" : p + self }
}
