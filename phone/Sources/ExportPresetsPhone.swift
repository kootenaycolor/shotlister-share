import Foundation

/// The iPhone's side of `shared/ExportPresets.swift`: the same presets as the
/// Mac, through the same server door.
extension ExportPresets {
    /// `-ExportCheck` on a simulator: a copy of its own, never the server.
    nonisolated static var platformChecking: Bool { ProcessInfo.processInfo.arguments.contains("-ExportCheck") }
    nonisolated static var platformFolder: String { "" }
    nonisolated static var platformSetupsKey: String { "export" }
    nonisolated static var platformMachine: String { "iphone" }
    nonisolated static func platformServer() -> (String, String)? {
        guard let address = PortalLine.address(), let token = PortalLine.token() else { return nil }
        return (address, token)
    }
}
