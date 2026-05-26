import Foundation

final class CodexIntegration: ToolIntegration {
    let id = "codex-cli"
    let displayName = "Codex CLI"
    let supportLevel: SupportLevel = .events

    var hooksPath:  String { "\(NSHomeDirectory())/.codex/hooks.json" }
    var configPath: String { "\(NSHomeDirectory())/.codex/config.toml" }
    var dir:        String { "\(NSHomeDirectory())/.codex" }

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
        let hasDir = fm.fileExists(atPath: dir)
        let hasCLI = isCommandAvailable("codex")

        guard hasDir || hasCLI else { return .toolNotInstalled }

        if fm.fileExists(atPath: hooksPath) {
            do {
                let dict = try JSONHookMerger.readJSON(hooksPath)
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
        if !fm.fileExists(atPath: dir) {
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        // 1. hooks.json — merge in our specs
        _ = try JSONHookMerger.backup(hooksPath)
        var dict = try JSONHookMerger.readJSON(hooksPath)
        JSONHookMerger.merge(into: &dict, specs: JSONHookMerger.codexHookSpecs)
        try JSONHookMerger.writeJSON(dict, to: hooksPath)

        // 2. config.toml — ensure `features.hooks = true`
        try ensureFeaturesHooksEnabled()
    }

    func uninstall() throws {
        _ = try JSONHookMerger.backup(hooksPath)
        var dict = try JSONHookMerger.readJSON(hooksPath)
        JSONHookMerger.removeMatching(&dict,
            fragments: JSONHookMerger.lightsCommandFragments)
        try JSONHookMerger.writeJSON(dict, to: hooksPath)
        // Don't touch features.hooks — user may need it for other tools.
    }

    /// Append `features.hooks = true` to config.toml if not present.
    /// No TOML parser — simple text scan.
    private func ensureFeaturesHooksEnabled() throws {
        let fm = FileManager.default
        var content = ""
        if fm.fileExists(atPath: configPath) {
            content = (try? String(contentsOfFile: configPath, encoding: .utf8)) ?? ""
        }
        // Already there (inline form)?
        if content.range(of: #"features\.hooks\s*=\s*true"#,
                         options: .regularExpression) != nil {
            return
        }
        // Already there inside [features] section?
        if content.contains("[features]"),
           content.range(of: #"(?m)^\s*hooks\s*=\s*true"#,
                         options: .regularExpression) != nil {
            return
        }
        _ = try? JSONHookMerger.backup(configPath)
        var newContent = content
        if !newContent.isEmpty && !newContent.hasSuffix("\n") { newContent += "\n" }
        newContent += "\n# Lights: enable lifecycle hooks subsystem\nfeatures.hooks = true\n"
        try newContent.write(toFile: configPath, atomically: true, encoding: .utf8)
    }
}
