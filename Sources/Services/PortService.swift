import Foundation

enum PortServiceError: LocalizedError {
    case lsofFailed(String)
    case killFailed(String, String)
    case unableToKill(String)

    var errorDescription: String? {
        switch self {
        case .lsofFailed(let msg): return "lsof 执行失败: \(msg)"
        case .killFailed(let pid, let msg): return "kill \(pid) 失败: \(msg)"
        case .unableToKill(let pid): return "无法终止进程 \(pid)，可能需要管理员权限"
        }
    }
}

struct PortService {

    /// 查询指定端口被哪些进程占用
    func query(_ port: String) throws -> [PortRecord] {
        let output = try run("/usr/sbin/lsof", arguments: ["-i", ":\(port)", "-P", "-n"])
        let records = parseLsofOutput(output)
        return enrichWithPsInfo(records)
    }

    /// 终止进程，优先 SIGTERM，失败后提权 SIGKILL
    func kill(pid: String) throws {
        do {
            _ = try run("/bin/kill", arguments: [pid])
        } catch {
            try killWithPrivileges(pid: pid)
        }
    }

    // MARK: - lsof 解析

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

            let proto = nameField.hasPrefix("TCP") ? "TCP"
                : (nameField.hasPrefix("UDP") ? "UDP" : "—")
            let port = extractPort(from: nameField)

            return PortRecord(
                pid: pid,
                processName: command,
                user: user,
                protocolType: proto,
                port: port,
                fullCommand: command,
                startTime: "—"
            )
        }
    }

    private func extractPort(from nameField: String) -> String {
        if let colonIndex = nameField.lastIndex(of: ":") {
            var port = String(nameField[nameField.index(after: colonIndex)...])
            if let paren = port.firstIndex(of: " ") {
                port = String(port[..<paren])
            }
            return port
        }
        return "—"
    }

    // MARK: - ps 补充详细信息

    private func enrichWithPsInfo(_ records: [PortRecord]) -> [PortRecord] {
        guard !records.isEmpty else { return records }

        let pids = records.map(\.pid)
        let pidList = pids.joined(separator: ",")

        // 分开两次调 ps，避免 args 和 lstart 字段内容互相干扰
        var cmdMap: [String: String] = [:]
        if let output = try? run("/bin/ps", arguments: ["-p", pidList, "-o", "pid=,args="]) {
            for line in output.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                guard let space = trimmed.firstIndex(of: " ") else { continue }
                let pid = String(trimmed[..<space])
                let cmd = String(trimmed[trimmed.index(after: space)...])
                cmdMap[pid] = cmd
            }
        }

        var timeMap: [String: String] = [:]
        if let output = try? run("/bin/ps", arguments: ["-p", pidList, "-o", "pid=,lstart="]) {
            for line in output.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                guard let space = trimmed.firstIndex(of: " ") else { continue }
                let pid = String(trimmed[..<space])
                let time = String(trimmed[trimmed.index(after: space)...])
                timeMap[pid] = time
            }
        }

        return records.map { record in
            PortRecord(
                pid: record.pid,
                processName: record.processName,
                user: record.user,
                protocolType: record.protocolType,
                port: record.port,
                fullCommand: cmdMap[record.pid] ?? record.fullCommand,
                startTime: timeMap[record.pid] ?? record.startTime
            )
        }
    }

    // MARK: - 命令执行

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
