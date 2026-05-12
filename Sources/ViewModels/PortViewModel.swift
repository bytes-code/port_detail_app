import Foundation
import Observation

@Observable
final class PortViewModel {

    var portInput = ""
    var processes: [PortRecord] = []
    var isLoading = false
    var errorMessage: String?
    var successMessage: String?
    var selectedIDs: Set<UUID> = []

    var selectedCount: Int { selectedIDs.count }

    var hasSelection: Bool { !selectedIDs.isEmpty }

    var isEmpty: Bool { !isLoading && errorMessage == nil && processes.isEmpty && !portInput.isEmpty }

    private let service = PortService()

    // MARK: - 输入校验

    func validatePort() -> String? {
        let trimmed = portInput.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty {
            return "请输入端口号"
        }
        guard let num = Int(trimmed) else {
            return "端口号必须为数字"
        }
        guard trimmed.allSatisfy({ $0.isNumber }) else {
            return "端口号必须为整数"
        }
        guard num >= 1, num <= 65535 else {
            return "端口号范围 1-65535"
        }
        return nil
    }

    // MARK: - 操作

    func search() {
        if let msg = validatePort() {
            errorMessage = msg
            return
        }

        errorMessage = nil
        successMessage = nil
        isLoading = true
        selectedIDs.removeAll()

        let port = portInput.trimmingCharacters(in: .whitespaces)

        Task.detached { [weak self] in
            guard let self else { return }
            do {
                let results = try self.service.query(port)
                await MainActor.run {
                    self.processes = results
                    self.isLoading = false
                }
            } catch {
                let message: String
                if let svcError = error as? PortServiceError {
                    message = svcError.localizedDescription
                } else {
                    message = error.localizedDescription
                }
                await MainActor.run {
                    self.processes = []
                    self.errorMessage = message
                    self.isLoading = false
                }
            }
        }
    }

    func refresh() {
        guard !portInput.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        search()
    }

    func killSelected() {
        let pids = processes.filter { selectedIDs.contains($0.id) }.map(\.pid)
        killPIDs(pids)
    }

    func killPIDs(_ pids: [String]) {
        guard !pids.isEmpty else { return }

        errorMessage = nil
        successMessage = nil

        for pid in pids {
            do {
                try service.kill(pid: pid)
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }

        successMessage = "已终止 \(pids.count) 个进程"
        selectedIDs.removeAll()
        refresh()
    }

    func killSingle(_ pid: String) {
        do {
            try service.kill(pid: pid)
            successMessage = "已终止进程 \(pid)"
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleSelection(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    func selectAll() {
        selectedIDs = Set(processes.map(\.id))
    }

    func deselectAll() {
        selectedIDs.removeAll()
    }
}
