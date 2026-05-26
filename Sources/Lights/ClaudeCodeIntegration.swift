import Foundation

final class ClaudeCodeIntegration: ToolIntegration {
    let id = "claude-code"
    let displayName = "Claude Code"
    let supportLevel: SupportLevel = .events

    var settingsPath: String { "\(NSHomeDirectory())/.claude/settings.json" }

    var statusBlurb: String {
        switch detectStatus() {
        case .toolNotInstalled:        return "Not installed"
        case .toolPresentHookMissing:  return "Installed — Lights hook missing"
        case .configured:              return "Hooks configured ✓"
        case .unknown(let why):        return "Error: \(why)"
        }
    }

    func detectStatus() -> InstallStatus {
        let fm = FileManager.default
        let hasSettings = fm.fileExists(atPath: settingsPath)
        let hasCLI = isCommandAvailable("claude")

        guard hasSettings || hasCLI else { return .toolNotInstalled }

        if hasSettings {
            do {
                let dict = try JSONHookMerger.readJSON(settingsPath)
                if JSONHookMerger.containsAnyHook(dict,
                    fragments: JSONHookMerger.lightsCommandFragments) {
                    return .configured
                }
            } catch {
                return .unknown(error.localizedDescription)
            }
        }
        return .toolPresentHookMissing
    }

    func install() throws {
        let fm = FileManager.default
        let dir = "\(NSHomeDirectory())/.claude"
        if !fm.fileExists(atPath: dir) {
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        _ = try JSONHookMerger.backup(settingsPath)
        var dict = try JSONHookMerger.readJSON(settingsPath)
        JSONHookMerger.merge(into: &dict, specs: JSONHookMerger.lightsHookSpecs)
        try JSONHookMerger.writeJSON(dict, to: settingsPath)
    }

    func uninstall() throws {
        _ = try JSONHookMerger.backup(settingsPath)
        var dict = try JSONHookMerger.readJSON(settingsPath)
        JSONHookMerger.removeMatching(&dict,
            fragments: JSONHookMerger.lightsCommandFragments)
        try JSONHookMerger.writeJSON(dict, to: settingsPath)
    }
}
