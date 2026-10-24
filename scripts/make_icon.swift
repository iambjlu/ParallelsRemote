// 把網頁用的 512 圖示(PWA.swift 內嵌的 PNG)轉成 macOS App 圖示 AppIcon.icns。
// macOS 圖示四周要留邊(約 10%),所以把圖縮成 80% 置中。
// 用法:swift scripts/make_icon.swift <輸出 .icns 路徑>
import AppKit
import Foundation

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let src = try String(contentsOf: root.appendingPathComponent("Sources/ParallelsRemote/PWA.swift"), encoding: .utf8)
guard let r = src.range(of: #"icon512 = Data\(base64Encoded: "([^"]+)""#, options: .regularExpression),
      let b64 = src[r].split(separator: "\"").dropFirst().first,
      let data = Data(base64Encoded: String(b64)), let img = NSImage(data: data) else {
    FileHandle.standardError.write(Data("找不到 icon512\n".utf8)); exit(1)
}

func png(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    let inset = CGFloat(px) * 0.1
    img.draw(in: NSRect(x: inset, y: inset, width: CGFloat(px) - inset * 2, height: CGFloat(px) - inset * 2))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let set = out.deletingPathExtension().appendingPathExtension("iconset")
try? FileManager.default.removeItem(at: set)
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for s in [16, 32, 128, 256, 512] {
    try png(s).write(to: set.appendingPathComponent("icon_\(s)x\(s).png"))
    try png(s * 2).write(to: set.appendingPathComponent("icon_\(s)x\(s)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set.path, "-o", out.path]
try p.run(); p.waitUntilExit()
try? FileManager.default.removeItem(at: set)
exit(p.terminationStatus)
