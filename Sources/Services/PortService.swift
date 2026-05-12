import Foundation

enum PortServiceError: LocalizedError {
    case lsofFailed(String)
    case killFailed(String, String) // pid + stderr
    case lsofNotFound
    case unableToKill(String)       // pid

    var errorDescription: String? {
        switch self {
        case .lsofFailed(let msg): return "lsof 执行失败: \(msg)"
        case .killFailed(let pid, let msg): return "kill \(pid) 失败: \(msg)"
        case .lsofNotFound: return "未找到 lsof 命令"
        case .unableToKill(let pid): return "无法终止进程 \(pid)，可能需要管理员权限"
        }
    }
}

struct PortService {

    /// 查询指定端口被哪些进程占用
    func query(_ port: String) throws -> [PortRecord] {
        let output = try run("/usr/sbin/lsof", arguments: ["-i", ":\(port)", "-P", "-n"])
        return parseLsofOutput(output)
    }

    /// 终止进程，优先 SIGTERM，失败后尝试 SIGKILL
    func kill(pid: String) throws {
        // 先尝试 SIGTERM
        do {
            let _ = try run("/bin/kill", arguments: [pid])
            return
        } catch {
            // SIGTERM 失败，用管理员权限执行 SIGKILL
            try killWithPrivileges(pid: pid)
        }
    }

    // MARK: - Private

    private func parseLsofOutput(_ output: String) -> [PortRecord] {
        let lines = output.components(separatedBy: "\n")
        guard lines.count > 1 else { return [] }

        return lines.dropFirst().compactMap { line in
            let cols = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard cols.count >= 9 else { return nil }

            let command = cols[0]
            let pid = cols[1]
            let user = cols[2]
            let nameField = cols[8]

            let proto = nameField.hasPrefix("TCP") ? "TCP" : (nameField.hasPrefix("UDP") ? "UDP" : "—")
            let port = extractPort(from: nameField)

            return PortRecord(
                pid: pid,
                processName: command,
                user: user,
                protocolType: proto,
                port: port
            )
        }
    }

    private func extractPort(from nameField: String) -> String {
        // nameField 格式: "TCP *:3000" 或 "TCP 127.0.0.1:3000->..."
        if let colonIndex = nameField.lastIndex(of: ":") {
            var port = String(nameField[nameField.index(after: colonIndex)...])
            // 去掉可能的后缀如 (LISTEN)
            if let paren = port.firstIndex(of: " ") {
                port = String(port[..<paren])
            }
            return port
        }
        return "—"
    }

    private func run(_ executable: String, arguments: [String]) throws -> String {
        let process = Foundation.Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""
            throw PortServiceError.lsofFailed(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return stdout
    }

    private func killWithPrivileges(pid: String) throws {
        let script = """
        do shell script "kill -9 \(pid)" with administrator privileges
        """

        let process = Foundation.Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""
            throw PortServiceError.killFailed(pid, stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
