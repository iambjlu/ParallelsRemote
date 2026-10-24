import Foundation

struct ShellResult {
    let status: Int32
    let out: String
    let err: String
}

struct ShellError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

/// 以參數陣列執行外部程式(絕不經過 shell,避免指令注入)。
enum Shell {
    static func run(_ exe: String, _ args: [String]) async throws -> ShellResult {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global().async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: exe)
                p.arguments = args
                let o = Pipe(), e = Pipe()
                p.standardOutput = o
                p.standardError = e
                do { try p.run() } catch {
                    cont.resume(throwing: ShellError(message: "無法執行 \(exe): \(error.localizedDescription)"))
                    return
                }
                // 兩條 pipe 同時讀取,避免輸出過多造成死鎖
                var errData = Data()
                let g = DispatchGroup()
                g.enter()
                DispatchQueue.global().async { errData = e.fileHandleForReading.readDataToEndOfFile(); g.leave() }
                let outData = o.fileHandleForReading.readDataToEndOfFile()
                g.wait()
                p.waitUntilExit()
                cont.resume(returning: ShellResult(
                    status: p.terminationStatus,
                    out: String(decoding: outData, as: UTF8.self),
                    err: String(decoding: errData, as: UTF8.self)))
            }
        }
    }

    /// 執行並在失敗時丟出錯誤。
    @discardableResult
    static func check(_ exe: String, _ args: [String]) async throws -> String {
        let r = try await run(exe, args)
        guard r.status == 0 else {
            let msg = (r.err.isEmpty ? r.out : r.err).trimmingCharacters(in: .whitespacesAndNewlines)
            throw ShellError(message: "\(URL(fileURLWithPath: exe).lastPathComponent) \(args.first ?? "") 失敗: \(msg)")
        }
        return r.out
    }
}
