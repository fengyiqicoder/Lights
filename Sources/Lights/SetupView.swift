import SwiftUI
import AppKit

struct SetupView: View {
    @ObservedObject var mgr: SetupManager = .shared
    var onDone: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            intro
            toolList
            Spacer(minLength: 0)
            footer
        }
        .frame(width: 500, height: 380)
        .onAppear { mgr.refreshAll() }
    }

    private var header: some View {
        HStack {
            Text("Lights Setup")
                .font(.title2.bold())
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    private var intro: some View {
        Text("Connect Lights to your AI coding tools. Lights must be running for hooks to reach it.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 12)
    }

    private var toolList: some View {
        VStack(spacing: 6) {
            ForEach(mgr.tools) { state in
                ToolRow(state: state, mgr: mgr)
            }
        }
        .padding(.horizontal, 20)
    }

    private var footer: some View {
        HStack {
            Text("Backups saved beside the config files.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Refresh") { mgr.refreshAll() }
            Button("Done") {
                SetupManager.markSetupSeen()
                onDone()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(20)
    }
}

private struct ToolRow: View {
    @ObservedObject var state: ToolIntegrationState
    let mgr: SetupManager

    var body: some View {
        HStack(spacing: 12) {
            badge.frame(width: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(state.tool.displayName).font(.body.weight(.medium))
                Text(state.tool.statusBlurb)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let err = state.lastError {
                    Text(err)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }

            Spacer()
            actionButton
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.4))
        )
    }

    @ViewBuilder
    private var badge: some View {
        switch state.status {
        case .configured:             dot(.green)
        case .toolPresentHookMissing: dot(.orange)
        case .toolNotInstalled:       dot(.gray)
        case .unknown:                dot(.red)
        }
    }

    private func dot(_ color: Color) -> some View {
        Circle().fill(color).frame(width: 10, height: 10)
    }

    @ViewBuilder
    private var actionButton: some View {
        switch (state.tool.supportLevel, state.status) {
        case (.notSupported, _):
            Text("N/A").font(.caption).foregroundStyle(.tertiary)
        case (.comingSoon, _):
            Text("v2").font(.caption).foregroundStyle(.tertiary)
        case (.events, .toolNotInstalled):
            Text("—").font(.caption).foregroundStyle(.tertiary)
        case (.events, .toolPresentHookMissing):
            Button("Install") { mgr.install(state) }
                .buttonStyle(.borderedProminent)
        case (.events, .configured):
            Button("Uninstall") { mgr.uninstall(state) }
        case (.events, .unknown):
            Button("Retry") { state.refresh() }
        }
    }
}
