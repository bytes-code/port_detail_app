import Foundation

struct PortRecord: Identifiable, Hashable {
    let id = UUID()
    let pid: String
    let processName: String
    let user: String
    let protocolType: String
    let port: String
    let fullCommand: String
    let startTime: String
}
