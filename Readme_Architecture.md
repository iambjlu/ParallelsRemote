# Parallels Remote 架構

## 總覽

```
手機瀏覽器 ──HTTP/HTTPS──▶ Mac 上的 SwiftUI App(選單列常駐)
                              ├─ HTTPServer   接收連線、來源限制、HTTPS 前門
                              ├─ Router       登入檢查、路由
                              ├─ Parallels    actor,執行 prlctl / prlsrvctl / cp -c
                              └─ Auth         密碼雜湊、登入 session、失敗鎖定
```

單一 SwiftPM 執行檔 `ParallelsRemote`(macOS 15+,Swift 5 語言模式),沒有第三方相依。

## 目錄結構

```
Package.swift
scripts/make_app.sh            打包成 .app(Info.plist、ad-hoc 簽章)
Sources/ParallelsRemote/
  App.swift                    App 進入點、AppState、選單列、設定視窗
  HTTPServer.swift             NWListener 簡易 HTTP 伺服器、HTTPS 前門
  Router.swift                 API 路由與登入檢查
  Parallels.swift              虛擬機 / 快照 / 網卡 / 轉發 / 複製 / 刪除
  Auth.swift                   密碼、session、登入失敗鎖定
  TLS.swift                    自簽憑證產生與載入
  Config.swift                 config.json
  Shell.swift                  外部程式執行(參數陣列,不經 shell)
  Web.swift                    單頁網頁(HTML + CSS + JS,整份是一個字串常數)
  PWA.swift                    manifest、service worker 與圖示(PNG 以 base64 內嵌)
```

## App.swift

**AppState**(`@MainActor`、`ObservableObject`、單例):持有 `Config`、`Parallels` actor、`Auth`、伺服器實例與設定視窗的狀態。

- `startServer()`:依 `config.https` 決定是否先載入 TLS identity,再建立 `HTTPServer` 並以 `Router` 處理請求。重複呼叫會先停掉舊的。
- `setHTTPS` / `regenerateCertificate`:切換 HTTPS、重新產生憑證後重啟伺服器。
- `setPassword` / `clearPassword`:委派給 `Auth`。
- `setLaunchAtLogin`:`SMAppService.mainApp`;不在 `.app` 內時不執行並在設定視窗提示。
- `localIPv4()`:`getifaddrs` 取得各網卡 IPv4,用於顯示連線網址與憑證 SAN。網卡名稱以 `SCNetworkInterface` 換成系統顯示名稱(例如 `en0` → Wi-Fi);沒有系統名稱的 VPN 通道,IP 在 `100.64.0.0/10` 的標為 Tailscale。只列出已啟用且執行中的介面,排除 loopback、link-local 以及虛擬機內部網路(`gif` / `vmnet` / `bridge`)。
- `applyPort`:驗證連接埠(1024–65535)後存檔並重啟服務。

**視窗與 Dock 行為**:

- 啟動時 `NSApp.setActivationPolicy(.accessory)`,只在選單列;主視窗 `Window(id: "main")` 設為 `.defaultLaunchBehavior(.suppressed)`,啟動時不自動開。
- 開啟主視窗(選單項目或 `applicationShouldHandleReopen`)時改為 `.regular`,Dock 出現圖示;`NSWindow.willCloseNotification` 偵測到主視窗關閉後改回 `.accessory`。
- `applicationShouldHandleReopen` 透過 `Notification` 通知常駐的 `MenuBarLabel`,由它呼叫 `openWindow` 開窗(AppDelegate 本身拿不到 `openWindow`)。
- 打包後的 `Info.plist` 設 `LSUIElement`,避免啟動瞬間閃出 Dock 圖示。

**選單列**(`MenuBarExtra`,視窗樣式):面板內用 SwiftUI `Grid` 排版,標籤欄與數值欄各自對齊(服務、協定、連接埠、登入密碼,以及「網卡名稱 → IP:埠」);點 IP 拷貝完整網址並短暫顯示打勾;底部是「開啟主視窗…」與「結束」。原生選單樣式(`.menu`)無法做欄位對齊,所以改用視窗樣式。

**設定視窗**(`SettingsView`):連線網址與連接埠、密碼設定(兩次輸入一致才能送出)、HTTPS 開關與重新產生憑證、登入時自動啟動、SSH 轉發起始埠、操作結果提示。

## HTTPServer.swift

以 `Network.framework` 的 `NWListener` 實作的最小 HTTP/1.1 伺服器:一個連線處理一個請求,回應後關閉(`Connection: close`)。

- **請求解析**:讀到 `\r\n\r\n` 後解析請求行、標頭(key 轉小寫)、query,再依 `Content-Length` 補讀 body;上限約 64KB。
- **來源限制**:`isAllowed` 只放行 IPv4 的 `10/8`、`172.16/12`、`192.168/16`、`100.64/10`(Tailscale)、`127/8`;IPv6 的 `::1`、`fd00::/8`、`fe80::/10`,以及 IPv4-mapped 位址依其 IPv4 判斷。其餘直接關閉連線。
- `HTTPRequest` 帶有 `remote`(來源位址,用於登入失敗鎖定)與 `secure`(是否 HTTPS);`HTTPResponse` 可帶額外標頭(例如 `Set-Cookie`)。
- 固定附加 `Cache-Control: no-store`、`X-Content-Type-Options: nosniff`。

**HTTPS 前門**:`NWListener` 的 TLS 在握手階段由系統處理,同一個埠收到明文 HTTP 時握手會直接失敗,無法回轉址。因此 HTTPS 模式分成兩層:

1. 內部 TLS 服務:只綁在 `127.0.0.1` 的隨機埠,使用自簽憑證的 identity。
2. 前門:綁在對外埠的純 TCP 監聽,讀第一個位元組:
   - `0x16`(TLS ClientHello)→ 連到內部 TLS 服務並雙向轉送位元組。
   - 其他 → 視為明文 HTTP,讀完標頭後回 `302`(GET/HEAD)或 `307`(其他方法)轉址到 `https://<Host><路徑>`。使用暫時性轉址,避免瀏覽器永久快取,之後關掉 HTTPS 也不會打不開。

經前門轉送後,內部服務看到的連線來源都是 `127.0.0.1`。前門建立內部連線後記下「內部連線的本機埠 → 真正的遠端位址」,內部服務處理請求時用 `realAddress` 換回真實來源,登入失敗鎖定才能依真實來源計算。

## Router.swift

`handle` 的順序:

1. `GET /`、`GET /index.html` → 回傳 `webPage`(不需登入,頁面本身沒有機敏資料)。
2. 不需登入的 API:`GET /api/session`、`POST /api/login`、`POST /api/logout`。
3. 已設定密碼時,其餘 API 必須帶有效的 `pr_session` Cookie,否則 `401`。
4. `route` 依路徑與方法分派。

Cookie 屬性:`HttpOnly`(網頁 JS 讀不到)、`SameSite=Strict`、`Path=/`、`Max-Age` 30 天;HTTPS 連線時加 `Secure`。

### API

| 方法 | 路徑 | 說明 |
|---|---|---|
| GET | `/api/session` | `{authRequired, authed}` |
| POST | `/api/login` | `{password}`;成功設定 Cookie |
| POST | `/api/logout` | 作廢目前 session |
| GET | `/api/state` | `{vms, forwards, host}`:機器清單(含 `ips`、`nics`、`hw`)、端口轉發與主機上限(`host.cpus`、`host.memMB`) |
| POST | `/api/vm/:id/spec` | `{cpus, memMB}`,修改 CPU 與記憶體;機器必須是關機狀態 |
| POST | `/api/vm/:id/{start,stop,kill,suspend,resume,pause,restart}` | 電源操作 |
| POST | `/api/vm/:id/clone` | `{name?, start?}`,APFS 複製 |
| POST | `/api/vm/:id/revert` | 回復到最後一個快照 |
| DELETE | `/api/vm/:id` | `{confirmName}`,必須與機器名稱相同才會刪除 |
| POST | `/api/vm/:id/nic/:netN/{connect,disconnect}` | 網卡拔掉 / 連回 |
| GET / POST | `/api/vm/:id/snapshots` | 列出 / 建立(`{name}`) |
| POST | `/api/vm/:id/snapshots/:sid/switch` | 還原到指定快照 |
| DELETE | `/api/vm/:id/snapshots/:sid` | 刪除快照 |
| POST | `/api/forwards` | `{proto, sourcePort, target, destPort}` |
| DELETE | `/api/forwards/:name` | 只能刪除本程式建立的規則(`pr-` 開頭) |

## Parallels.swift

`actor Parallels`,所有改動狀態的操作都經過這個 actor 序列化(例如轉發埠的分配)。

**輸入驗證**:VM 與快照 ID 必須符合 UUID 格式(可含大括號);網卡名稱必須符合 `^net\d+$`;名稱不可含路徑字元。所有外部程式都以參數陣列執行,不經 shell。

### 與 Parallels 指令的對應

| 功能 | 指令 |
|---|---|
| 機器清單 | `prlctl list -a -f --json` |
| IP、網卡與規格 | `prlctl list -i <id> --json`(`Network.ipAddresses`、`Hardware.netN`、`Hardware.cpu.cpus`、`Hardware.memory.size`) |
| 修改規格 | `prlctl set <id> --cpus N --memsize MB` |
| 電源 | `prlctl start / stop / stop --kill / suspend / resume / pause / restart` |
| 快照 | `prlctl snapshot / snapshot-list --json / snapshot-switch / snapshot-delete` |
| 網卡 | `prlctl set <id> --device-connect|--device-disconnect netN` |
| 轉發 | `prlsrvctl net set <網路> --nat-<tcp|udp>-add 規則名,來源埠,目標,目標埠` / `--nat-<tcp|udp>-del 規則名` |
| 轉發清單 | `prlsrvctl net info <網路>`(文字輸出)與 `--json`(規則名稱) |
| 網段 | `prlsrvctl net info <網路> --json`(`Parallels adapter`) |
| 複製 | `cp -c -R` → `prlctl register --regenerate-src-uuid -n` → `prlctl set --device-set netN --mac auto` |
| 刪除 | `prlctl stop --kill`(若在執行)→ `prlctl delete` |

### 重要行為

- **規格(CPU / 記憶體)**:`listVMs` 對所有狀態的機器都查 `list -i`,把 `cpus` 與 `memMB` 放進 `hw`(IP 與網卡仍只處理執行中的機器)。`setSpec` 驗證 CPU 介於 1 到主機核心數、記憶體介於 256MB 到主機實體記憶體,並要求機器為 `stopped`(Parallels 不允許修改執行中 / 休眠機器的硬體),否則回 `409`。

- **IP 與網卡類型**:`ip_configured` 只回報第一個 IP,所以對執行中的機器另查 `list -i` 取得全部 IPv4。Parallels 不提供「IP 屬於哪張網卡」,改依 IP 所在網段判斷:落在 Shared / Host-Only 虛擬網路網段的標示為對應類型,其餘標示為 Bridged。某類網卡全部被拔掉時,殘留的舊 IP 會被過濾掉。
- **轉發規則清單**:`net info --json` 裡未命名的規則 key 都是空字串且會重複,無法正確解析,所以規則本身以文字輸出解析,JSON 只用來對照名稱。沒有名稱的既有規則在網頁上為唯讀。
- **複製**:副本放在來源的同一個資料夾(同一個 APFS 磁區才能 clone);名稱不可重複。來源是執行中時,先 `suspend`,複製完成(或失敗)後一定 `resume`。來源是休眠 / 執行中被休眠時,Parallels 不允許修改休眠機器的設定,所以複製後先刪除副本資料夾裡的 `*.mem`、`config.sav`、`suspended.png`(只動副本),副本會以冷開機啟動,之後才能重設所有網卡的 MAC。複製完成後自動建立一條 SSH 轉發(從 `sshBasePort + 1` 起第一個未使用的埠)。
- **刪除**:伺服器要求請求帶上與機器名稱完全相同的 `confirmName`;網頁在按鈕確認後自動帶入。刪除時一併移除指向該機器、由本程式建立的轉發規則。
- **回復到最後一個快照**:優先使用 `current` 的快照,沒有則取日期最新的。這個操作會丟棄快照之後的所有變更。

## Auth.swift

- 密碼以 PBKDF2-HMAC-SHA256(20 萬次、隨機 16 位元組 salt)雜湊後存入 `auth.json`,格式 `pbkdf2$<次數>$<salt>$<hash>`;驗證使用固定時間比較。
- 登入成功發出 32 位元組隨機 token,只儲存其 SHA-256 與到期時間;session 持久化,App 重啟後仍有效。更換 / 清除密碼會清空所有 session。
- 登入失敗鎖定:同一來源位址連續錯 5 次鎖 60 秒。
- `isRequired`:有密碼才為 true;沒有密碼時所有 API 不需登入。
- 密碼只能在 Mac 端的設定視窗設定,網頁端沒有設定或重設密碼的入口。

## TLS.swift

- 以 `/usr/bin/openssl` 產生 2048 位元 RSA 自簽憑證(825 天),SAN 包含 `localhost`、本機主機名稱、`.local` 名稱與各網卡 IPv4;再打包成 PKCS#12。
- 以 `SecPKCS12Import` + `kSecImportToMemoryOnly` 載入 identity,不寫入鑰匙圈,不會跳授權視窗。
- 憑證與私鑰存放在 `tls/`(權限 0600)。網卡 IP 改變後,到設定視窗按「重新產生憑證」。

## Config.swift 與資料位置

`~/Library/Application Support/ParallelsRemote/`:

| 檔案 | 內容 |
|---|---|
| `config.json` | `https`、`port`(預設 8888,設定視窗可改)、`networkName`、`sshBasePort`、`guestSSHPort` |
| `auth.json` | 密碼雜湊與 session(權限 0600) |
| `tls/` | `cert.pem`、`key.pem`、`identity.p12`、`openssl.cnf` |

## Shell.swift

`Shell.run` / `Shell.check` 以 `Process` 執行外部程式,stdout 與 stderr 同時讀取避免管線塞滿而死鎖;`check` 在結束碼非 0 時丟出帶有錯誤輸出的 `ShellError`。

## PWA.swift

提供 `/manifest.webmanifest`(`display: standalone`)、`/sw.js`(不快取任何內容的最精簡 service worker,只為了讓瀏覽器視為可安裝)與三個圖示:`/icon-192.png`、`/icon-512.png`、`/icon-maskable-512.png`。這些資源不含機敏資料,不需要登入,由 `Router.pwaAsset` 在登入檢查之前直接回傳。

iOS 加到主畫面時使用 `apple-touch-icon`(滿版 180x180),而且圖示是由系統另外下載;自簽憑證下那個下載會失敗,圖示就不會出現。因此這張圖以 `data:` 網址直接內嵌在 HTML 的 `<link rel="apple-touch-icon">`(`PWA.appleTouchIconBase64`),不需要另外下載。已經加到主畫面的捷徑不會自動更新圖示,需要刪掉重加。圖示是程式產生的 PNG(深灰底、金色三層伺服器機架),以 base64 內嵌。service worker 只在 secure context 註冊,失敗不影響一般使用。

## Web.swift(單頁網頁)

整個前端是一個字串常數,由 `GET /` 回傳。外觀參考 DragonVM 的冷灰 + 琥珀金配色,為節省手機 GPU 不使用 `backdrop-filter`、光暈陰影與動畫。字型使用系統字型並以非阻塞方式載入 Google Fonts 的 Inter(外網不通時頁面也不會卡住)。

- **版面**:每台機器一張卡片,預設只顯示狀態圓點與名稱;展開後依序為狀態與 IP、電源按鈕列、規格、網卡、端口轉發、快照。電源按鈕列使用圖示。
- **規格區塊**(`partSpec`):預設收合的 `details`(展開狀態記在 `openSpecs`,區塊重畫時保留),標題列顯示「N 核心 · X GB」,展開後提供 CPU(1 到主機核心數,步進 1)與記憶體(512MB 到主機記憶體,步進 256MB)兩條滑桿,樣式參考 DragonGuardian 的 `.form-slider`:灰色軌道(`.slider-wrap::before`)上疊獨立的金色填充 `.slider-fill`(兩端全圓角,右端為半圓結尾,停止點對齊把手中心 `calc(比例 * (100% - 18px) + 9px)`)、橢圓玻璃把手,以及刻度與數字(`.slider-ticklabels`,位置用同一條公式才會對準把手)。刻度:最左是最小值(1 核 / 0.5 GB),之後每個整數單位(核心數 / GB)一個點,最右是機器上限;數字最多標 7 個且等距(間隔取能整除的最小值,讓上限一定有數字),最小值與上限以外的數字都是整數(最小值 0.5 GB 為唯一的小數)。
- **差異更新**:每張卡片拆成 `head / ips / actions / spec / nics / fw` 區塊,各自計算內容特徵(`partSigs`);刷新時只替換特徵有變的區塊,沒變的 DOM 節點完全不動,因此展開狀態、輸入到一半的欄位、捲動位置都會保留。卡片以 UUID 為鍵,新增 / 移除 / 排序只動有差異的節點。快照清單在展開時靜默重抓,內容沒變就不替換。
- **刷新時機**:頁面載入、操作完成後,以及點擊畫面任何位置(0.4 秒內連點只刷新一次)。同時只跑一個刷新,刷新途中又被要求時在結束後補跑一次。
- **對話框**:`dgDialog` 取代瀏覽器原生 `alert / confirm / prompt`,按鈕為全寬堆疊;`dgConfirm`、`dgPrompt` 為其包裝。取消操作以 `CANCEL` 物件表示,按鈕處理函式會靜默結束而不顯示錯誤。
- **登入**:任何 API 回 `401` 時自動跳出密碼對話框,成功後重試原請求。登入是必要步驟,所以對話框是 `modal`:沒有取消鈕,點旁邊空白處也不會關閉。已設定密碼時右上角出現人頭圖示,點開確認後登出,登出完成會 `location.reload()` 重新載入頁面,清掉殘留的機器清單與狀態。
- **拷貝**:區網 `http://` 不是 secure context,`navigator.clipboard` 不可用,所以使用 `textarea` + `execCommand('copy')` 後備;失敗時會明確顯示失敗,不假裝成功。
- **iOS 獨立視窗的標題列保底**:加到主畫面後 `env(safe-area-inset-top)` 不一定可靠,標題列會被動態島 / 狀態列蓋住。頁面載入時若 `navigator.standalone === true` 且螢幕長邊為動態島機型的高度(852 / 874 / 932 / 956),就設定 CSS 變數 `--sat: 62px`;標題列頂部間距為 `max(env(safe-area-inset-top), var(--sat, 0px)) + 16px`,所以兩者取較大者。
- **標題列**:`position: sticky`,`z-index: 50`(低於對話框的 100,高於所有卡片)。不使用 `will-change` / `translateZ`:這會讓 iOS 以低解析度點陣化該圖層,文字會變糊。
- **PWA 與安全區域**:`viewport-fit=cover` 搭配 iOS 的 `black-translucent` 狀態列時,內容會延伸到狀態列 / 動態島底下,所以標題列、主要內容與提示訊息都用 `env(safe-area-inset-*)` 留出安全區域。
- **禁止雙擊放大與選取文字**:`touch-action: manipulation`、`user-select: none`(輸入框例外)。

## 安全設計摘要

- 來源限制(僅內網)是第一層;密碼登入是第二層;HTTPS 避免密碼以明文傳送。
- 外部指令一律以參數陣列執行並驗證輸入。
- 會刪除資料的操作需要二次確認:網頁以對話框確認,刪除機器的 API 另要求帶上機器名稱。
- 登入 Cookie 為 `HttpOnly`、`SameSite=Strict`(HTTPS 時 `Secure`);失敗會鎖定來源。

## 已知限制

- 複製出的 Linux 機器可能與原機取得相同 IP(`machine-id` 相同,DHCP 視為同一台)。
- 執行中複製的副本為冷開機,未存檔的資料不會帶過去。
- 網卡拔掉 / 連回只能對執行中的機器操作。
- 不支援 Passkeys / WebAuthn:需要網域名稱,無法使用 IP 位址連線。
- 開機自動啟動需要打包後的 `.app`。
