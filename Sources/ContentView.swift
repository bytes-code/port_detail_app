import SwiftUI

struct ContentView: View {
    @State private var vm = PortViewModel()
    @State private var showKillConfirm = false
    @State private var pendingKillPIDs: [String] = []
    @State private var pendingKillCount = 0

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            resultArea
            Divider()
            bottomBar
        }
        .frame(minWidth: 700, minHeight: 500)
        .alert("确认终止进程", isPresented: $showKillConfirm) {
            Button("取消", role: .cancel) {}
            Button("强制终止", role: .destructive) {
                vm.killPIDs(pendingKillPIDs)
                pendingKillPIDs = []
            }
        } message: {
            Text("确定要终止这 \(pendingKillCount) 个进程吗？\n进程将被强制终止 (kill -9)。")
        }
    }

    // MARK: - 搜索栏

    private var searchBar: some View {
        HStack(spacing: 8) {
            Text("端口号:")
                .font(.body)

            TextField("输入端口号", text: $vm.portInput)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
                .disabled(vm.isLoading)
                .onSubmit { vm.search() }

            Button(action: vm.search) {
                if vm.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                } else {
                    Label("查询", systemImage: "magnifyingglass")
                }
            }
            .disabled(vm.isLoading)
            .keyboardShortcut(.return, modifiers: [])

            Button(action: vm.refresh) {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .disabled(vm.portInput.trimmingCharacters(in: .whitespaces).isEmpty)
            .keyboardShortcut("r", modifiers: .command)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - 结果区

    @ViewBuilder
    private var resultArea: some View {
        if let error = vm.errorMessage {
            errorBanner(error)
        }

        if vm.isLoading {
            Spacer()
            ProgressView("查询中...")
                .padding(.bottom, 16)
            Spacer()
        } else if vm.processes.isEmpty && !vm.portInput.isEmpty {
            Spacer()
            Text("该端口未被占用")
                .foregroundColor(.secondary)
            Spacer()
        } else if vm.processes.isEmpty {
            Spacer()
            Text("输入端口号开始查询")
                .foregroundColor(.secondary)
            Spacer()
        } else {
            processTable
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(message)
                .foregroundColor(.red)
            Spacer()
            Button("关闭") {
                vm.errorMessage = nil
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.red.opacity(0.1))
    }

    // MARK: - 进程表格

    private var processTable: some View {
        Table(vm.processes, selection: $vm.selectedIDs) {
            TableColumn("PID") { record in
                Text(record.pid)
                    .monospacedDigit()
            }
            .width(70)

            TableColumn("进程名") { record in
                Text(record.processName)
                    .fontWeight(.medium)
            }
            .width(150)

            TableColumn("用户") { record in
                Text(record.user)
            }
            .width(100)

            TableColumn("协议") { record in
                Text(record.protocolType)
            }
            .width(60)

            TableColumn("端口") { record in
                Text(record.port)
                    .monospacedDigit()
            }
            .width(60)

            TableColumn("操作") { record in
                Button("Kill") {
                    killSingleConfirm(record)
                }
                .buttonStyle(.borderless)
                .foregroundColor(.red)
            }
            .width(60)
        }
        .contextMenu(forSelectionType: UUID.self) { selectedIDs in
            if !selectedIDs.isEmpty {
                Button("Kill 选中进程") {
                    pendingKillPIDs = selectedIDs.compactMap { id in
                        vm.processes.first(where: { $0.id == id })?.pid
                    }
                    pendingKillCount = pendingKillPIDs.count
                    showKillConfirm = true
                }
            }
        }
    }

    // MARK: - 底部栏

    private var bottomBar: some View {
        HStack {
            if let success = vm.successMessage {
                Label(success, systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }

            Spacer()

            if !vm.processes.isEmpty {
                Text("已选中 \(vm.selectedCount) 个进程")
                    .foregroundColor(.secondary)

                Button("全选") { vm.selectAll() }
                    .disabled(vm.selectedCount == vm.processes.count)

                Button("取消全选") { vm.deselectAll() }
                    .disabled(vm.selectedCount == 0)

                Button(role: .destructive) {
                    pendingKillPIDs = vm.processes.filter { vm.selectedIDs.contains($0.id) }.map(\.pid)
                    pendingKillCount = pendingKillPIDs.count
                    showKillConfirm = true
                } label: {
                    Label("Kill 选中", systemImage: "trash")
                }
                .disabled(!vm.hasSelection)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - 快捷 Kill

    private func killSingleConfirm(_ record: PortRecord) {
        pendingKillPIDs = [record.pid]
        pendingKillCount = 1
        showKillConfirm = true
    }
}
