import Foundation
import SwiftUI

final class ToolIntegrationState: ObservableObject, Identifiable {
    let tool: ToolIntegration
    @Published var status: InstallStatus = .toolNotInstalled
    @Published var lastError: String?

    var id: String { tool.id }

    init(tool: ToolIntegration) {
        self.tool = tool
    }

    @MainActor
    func refresh() {
        status = tool.detectStatus()
    }
}

@MainActor
final class SetupManager: ObservableObject {
    static let shared = SetupManager()
    @Published var tools: [ToolIntegrationState]

    private init() {
        let initial = [
            ToolIntegrationState(tool: ClaudeCodeIntegration()),
            ToolIntegrationState(tool: CodexIntegration()),
            ToolIntegrationState(tool: GooseIntegration()),
            ToolIntegrationState(tool: OpenCodeIntegration()),
        ]
        for s in initial { s.status = s.tool.detectStatus() }
        tools = initial
    }

    func refreshAll() {
        for t in tools { t.refresh() }
    }

    func install(_ state: ToolIntegrationState) {
        state.lastError = nil
        do {
            try state.tool.install()
            state.refresh()
        } catch {
            state.lastError = error.localizedDescription
        }
    }

    func uninstall(_ state: ToolIntegrationState) {
        state.lastError = nil
        do {
            try state.tool.uninstall()
            state.refresh()
        } catch {
            state.lastError = error.localizedDescription
        }
    }

    // MARK: - First-launch flag

    private static var seenFlagPath: String {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("Lights/seen-setup.flag").path
    }

    static var hasSeenSetup: Bool {
        FileManager.default.fileExists(atPath: seenFlagPath)
    }

    static func markSetupSeen() {
        let path = seenFlagPath
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: path, contents: nil)
    }
}
