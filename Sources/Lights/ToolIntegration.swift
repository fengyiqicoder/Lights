import Foundation

enum SupportLevel {
    case events           // Real implementation: full event hooks
    case comingSoon       // Tool exists but integration not yet written
    case notSupported     // Tool has no event hooks at all
}

enum InstallStatus: Equatable {
    case toolNotInstalled
    case toolPresentHookMissing
    case configured
    case unknown(String)
}

enum ToolIntegrationError: Error, LocalizedError {
    case invalidJSON(String)
    case writeFailed(String)
    case notImplemented(String)

    var errorDescription: String? {
        switch self {
        case .invalidJSON(let p):  return "Invalid JSON in: \(p)"
        case .writeFailed(let p):  return "Failed to write: \(p)"
        case .notImplemented(let t): return "\(t) integration not yet implemented"
        }
    }
}

protocol ToolIntegration: AnyObject {
    var id: String { get }
    var displayName: String { get }
    var supportLevel: SupportLevel { get }
    var statusBlurb: String { get }

    func detectStatus() -> InstallStatus
    func install() throws
    func uninstall() throws
}

extension ToolIntegration {
    func isCommandAvailable(_ cmd: String) -> Bool {
        let task = Process()
        task.launchPath = "/usr/bin/which"
        task.arguments = [cmd]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        do { try task.run() } catch { return false }
        task.waitUntilExit()
        return task.terminationStatus == 0
    }
}
