import SwiftUI
import AppKit
import Network
import ServiceManagement
import SystemConfiguration

extension Notification.Name {
    static let openMainWindow = Notification.Name("ParallelsRemote.openMainWindow")
}

let mainWindowTitle = "Parallels Remote"

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var config = Config.load()
    @Published var serverStatus = "啟動中…"
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var hasPassword = false
    /// 設定視窗裡顯示的操作結果(密碼、憑證、開機啟動等)
    @Published var notice = ""

    let prl: Parallels
    let auth = Auth()
    private var server: HTTPServer?

    private init() {
        prl = Parallels(config: Config.load())
        hasPassword = auth.hasPassword
    }

    var scheme: String { config.https == true ? "https" : "http" }

    /// 各網路介面的連線網址(含 Tailscale)
    var urls: [(name: String, url: String, ipPort: String)] {
        Self.localIPv4().map { ($0.0, "\(scheme)://\($0.1):\(config.port)/", "\($0.1):\(config.port)") }
    }

    // MARK: 伺服器

    func startServer() async {
        server?.stop()
        server = nil
        var identity: SecIdentity?
        if config.https == true {
            do { identity = try await TLS.loadIdentity(hosts: tlsHosts()) }
            catch { serverStatus = "HTTPS 憑證失敗:\(error)"; return }
        }
        let router = Router(prl: prl, auth: auth)
        do {
            let s = try HTTPServer(port: config.port, identity: identity) { await router.handle($0) }
            s.start { state in
                Task { @MainActor in AppState.shared.serverStatus = Self.describe(state) }
            }
            server = s
        } catch {
            serverStatus = "啟動失敗:\(error)"
        }
    }

    private static func describe(_ s: NWListener.State) -> String {
        switch s {
        case .ready: return "執行中"
        case .failed(let e): return "失敗:\(e)"
        case .waiting(let e): return "等待中:\(e)"
        case .cancelled: return "已停止"
        default: return "啟動中…"
        }
    }

    private func tlsHosts() -> [String] {
        let host = ProcessInfo.processInfo.hostName
        var h = ["localhost", "127.0.0.1", host, host.replacingOccurrences(of: ".local", with: "") + ".local"]
        h += Self.localIPv4().map { $0.1 }
        return h
    }

    func save() {
        config.save()
        let c = config
        Task { await prl.update(c) }
    }

    // MARK: 設定動作

    /// 套用新的連接埠並重啟服務(手機要改用新的網址)
    func applyPort(_ text: String) {
        guard let p = UInt16(text.trimmingCharacters(in: .whitespaces)), p >= 1024 else {
            notice = "連接埠必須是 1024 到 65535 之間的數字"
            return
        }
        guard p != config.port else { return }
        config.port = p
        save()
        notice = "已改用連接埠 \(p),手機請改用新的網址"
        Task { await startServer() }
    }

    func setHTTPS(_ on: Bool) {
        config.https = on
        save()
        notice = on ? "已切換為 HTTPS(自簽憑證,瀏覽器會警告,可略過)" : "已切換為 HTTP"
        Task { await startServer() }
    }

    func regenerateCertificate() {
        notice = "重新產生憑證中…"
        Task {
            do {
                _ = try await TLS.loadIdentity(hosts: tlsHosts(), regenerate: true)
                notice = "已重新產生憑證"
                if config.https == true { await startServer() }
            } catch { notice = "產生憑證失敗:\(error)" }
        }
    }

    func setPassword(_ pw: String) {
        auth.setPassword(pw)
        hasPassword = true
        notice = "密碼已設定,所有已登入的裝置都需要重新登入"
    }

    func clearPassword() {
        auth.clearPassword()
        hasPassword = false
        notice = "已清除密碼,網頁不再需要登入"
    }

    func setLaunchAtLogin(_ on: Bool) {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            notice = "開機自動啟動需要把程式包成 .app(執行 scripts/make_app.sh)"
            launchAtLogin = false
            return
        }
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            notice = on ? "已設定開機自動啟動" : "已取消開機自動啟動"
        } catch { notice = "開機啟動設定失敗:\(error.localizedDescription)" }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        notice = "已拷貝 \(text)"
    }

    /// 各網路介面的 IPv4:回傳 (顯示名稱, IP)。
    /// 顯示名稱沿用 DragonVM 的做法,用 SCNetworkInterface 把 en0 換成系統上的名稱(例如 Wi-Fi);
    /// 沒有系統名稱的 VPN 通道(utun)若在 Tailscale 位址範圍就標成 Tailscale,否則保留原名。
    /// 排除 loopback、link-local 與虛擬機內部網路(gif / vmnet / bridge)。
    static func localIPv4() -> [(String, String)] {
        var display: [String: String] = [:]
        for case let iface as SCNetworkInterface in (SCNetworkInterfaceCopyAll() as? [Any]) ?? [] {
            if let bsd = SCNetworkInterfaceGetBSDName(iface) as String?,
               let name = SCNetworkInterfaceGetLocalizedDisplayName(iface) as String? { display[bsd] = name }
        }
        var out: [(String, String)] = []
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return out }
        defer { freeifaddrs(ifap) }
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(p.pointee.ifa_flags)
            guard flags & (IFF_UP | IFF_RUNNING) == (IFF_UP | IFF_RUNNING), flags & IFF_LOOPBACK == 0,
                  let sa = p.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            let bsd = String(cString: p.pointee.ifa_name)
            if bsd.hasPrefix("gif") || bsd.hasPrefix("vmnet") || bsd.hasPrefix("bridge") { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            let ip = String(cString: host)
            if ip.hasPrefix("127.") || ip.hasPrefix("169.254.") { continue }
            out.append((display[bsd] ?? (isTailscale(ip) ? "Tailscale" : bsd), ip))
        }
        return out
    }

    /// Tailscale 使用 CGNAT 位址範圍 100.64.0.0/10
    private static func isTailscale(_ ip: String) -> Bool {
        let p = ip.split(separator: ".").compactMap { Int($0) }
        return p.count == 4 && p[0] == 100 && (64...127).contains(p[1])
    }
}

/// 主視窗開著時 Dock 要有圖示(.regular),關掉後 Dock 圖示消失、只剩選單列(.accessory)。
@MainActor
func showMainWindow(_ open: OpenWindowAction) {
    NSApp.setActivationPolicy(.regular)
    open(id: "main")
    NSApp.activate(ignoringOtherApps: true)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)   // 啟動時只在選單列,不出現 Dock 圖示
        Task { @MainActor in await AppState.shared.startServer() }

        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
            guard let w = note.object as? NSWindow, w.title == mainWindowTitle else { return }
            // 等視窗真的關掉後再收回 Dock 圖示
            DispatchQueue.main.async { NSApp.setActivationPolicy(.accessory) }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { false }

    /// 從 Finder / Spotlight 再次開啟 App 時,叫出主視窗
    func applicationShouldHandleReopen(_ app: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { NotificationCenter.default.post(name: .openMainWindow, object: nil) }
        return true
    }
}

@main
struct ParallelsRemoteApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)   // 視窗樣式才能用 Grid 讓標籤與 IP 的起點對齊

        Window(mainWindowTitle, id: "main") { SettingsView() }
            .defaultSize(width: 480, height: 640)
            .defaultLaunchBehavior(.suppressed)   // 啟動時不自動開視窗,只在選單列
    }
}

struct MenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: "server.rack")
            .onReceive(NotificationCenter.default.publisher(for: .openMainWindow)) { _ in
                showMainWindow(openWindow)
            }
    }
}

struct MenuContent: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var state = AppState.shared
    /// 剛拷貝的網址,短暫顯示打勾回饋
    @State private var copied: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 標籤欄與數值欄各自對齊(Grid 讓每一列的第二欄起點相同)
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                row("服務", state.serverStatus)
                row("協定", state.scheme.uppercased())
                row("連接埠", String(state.config.port))
                row("登入密碼", state.hasPassword ? "已設定" : "未設定")
            }

            Divider()

            Text("連線網址(點一下拷貝)").font(.caption).foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                ForEach(state.urls, id: \.url) { item in
                    GridRow {
                        Text(item.name).foregroundStyle(.secondary)
                        Button {
                            state.copy(item.url)
                            copied = item.url
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { if copied == item.url { copied = nil } }
                        } label: {
                            HStack(spacing: 6) {
                                Text(item.ipPort)
                                if copied == item.url { Image(systemName: "checkmark").foregroundStyle(.green) }
                            }
                        }
                        .buttonStyle(.plain)
                        .help(item.url)
                    }
                }
            }

            Divider()

            HStack {
                Button("開啟主視窗…") { showMainWindow(openWindow) }
                Spacer()
                Button("結束") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value)
        }
    }
}

struct SettingsView: View {
    @ObservedObject private var state = AppState.shared
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var portText = ""

    private var passwordOK: Bool { !newPassword.isEmpty && newPassword == confirmPassword }

    private var httpsBinding: Binding<Bool> {
        Binding(get: { state.config.https == true }, set: { state.setHTTPS($0) })
    }
    private var launchBinding: Binding<Bool> {
        Binding(get: { state.launchAtLogin }, set: { state.setLaunchAtLogin($0) })
    }

    var body: some View {
        Form {
            Section("連線") {
                LabeledContent("服務狀態", value: state.serverStatus)
                LabeledContent("連接埠") {
                    HStack {
                        TextField("", text: $portText).multilineTextAlignment(.trailing).frame(width: 80)
                            .onSubmit { state.applyPort(portText) }
                        Button("套用") { state.applyPort(portText) }
                    }
                }
                ForEach(state.urls, id: \.url) { item in
                    LabeledContent(item.name) {
                        HStack {
                            Text(item.url).font(.caption).textSelection(.enabled)
                            Button("拷貝") { state.copy(item.url) }
                        }
                    }
                }
            }

            Section {
                SecureField("新密碼", text: $newPassword)
                SecureField("再輸入一次", text: $confirmPassword)
                HStack {
                    Button(state.hasPassword ? "更換密碼" : "設定密碼") {
                        state.setPassword(newPassword)
                        newPassword = ""; confirmPassword = ""
                    }
                    .disabled(!passwordOK)
                    if state.hasPassword {
                        Button("清除密碼", role: .destructive) { state.clearPassword() }
                    }
                }
                if !confirmPassword.isEmpty && newPassword != confirmPassword {
                    Text("兩次輸入的密碼不一致").font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("登入密碼")
            } footer: {
                Text(state.hasPassword
                     ? "已設定密碼:網頁需要輸入密碼才能控制。更換密碼會登出所有裝置。"
                     : "尚未設定密碼:同一個網路內的人都能直接控制虛擬機。")
            }

            Section {
                Toggle("使用 HTTPS(自簽憑證)", isOn: httpsBinding)
                Button("重新產生憑證") { state.regenerateCertificate() }
            } header: {
                Text("HTTPS")
            } footer: {
                Text("自簽憑證不受信任,瀏覽器會顯示警告,可略過。HTTPS 讓網頁成為安全環境,輸入密碼也不會以明文傳送。")
            }

            Section("一般") {
                Toggle("登入時自動啟動", isOn: launchBinding)
                Stepper("SSH 轉發起始埠:\(state.config.sshBasePort)", value: $state.config.sshBasePort, in: 1024...64000)
                    .onChange(of: state.config.sshBasePort) { _, _ in state.save() }
            }

            if !state.notice.isEmpty {
                Section { Text(state.notice).font(.callout).foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            portText = String(state.config.port)
            // 主視窗開啟期間 Dock 要有圖示
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
