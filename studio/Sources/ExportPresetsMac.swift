import Foundation

/// The Mac's side of `shared/ExportPresets.swift`.
extension ExportPresets {
    nonisolated static var platformChecking: Bool { Launch.checking }
    nonisolated static var platformFolder: String { "Shotlister/" }
    nonisolated static var platformSetupsKey: String { Launch.checking ? "export.checking" : "export" }
    nonisolated static var platformMachine: String { Host.current().localizedName ?? "mac" }
    nonisolated static func platformServer() -> (String, String)? {
        guard let address = SpecSheets.address(), let token = SpecSheets.token() else { return nil }
        return (address, token)
    }
}
