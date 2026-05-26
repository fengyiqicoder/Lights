import Foundation

final class GooseIntegration: ToolIntegration {
    let id = "goose"
    let displayName = "Goose"
    let supportLevel: SupportLevel = .comingSoon

    var statusBlurb: String {
        isCommandAvailable("goose")
            ? "Installed — hooks API still being researched (v2)"
            : "Not installed"
    }

    func detectStatus() -> InstallStatus {
        isCommandAvailable("goose") ? .toolPresentHookMissing : .toolNotInstalled
    }

    func install() throws   { throw ToolIntegrationError.notImplemented("Goose") }
    func uninstall() throws { throw ToolIntegrationError.notImplemented("Goose") }
}

final class OpenCodeIntegration: ToolIntegration {
    let id = "opencode"
    let displayName = "OpenCode"
    let supportLevel: SupportLevel = .notSupported

    var statusBlurb: String {
        isCommandAvailable("opencode")
            ? "Installed — OpenCode has no event hooks"
            : "Not installed"
    }

    func detectStatus() -> InstallStatus {
        isCommandAvailable("opencode") ? .toolPresentHookMissing : .toolNotInstalled
    }

    func install() throws   { throw ToolIntegrationError.notImplemented("OpenCode") }
    func uninstall() throws { throw ToolIntegrationError.notImplemented("OpenCode") }
}
