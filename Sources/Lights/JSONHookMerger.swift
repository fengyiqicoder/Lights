import Foundation

struct HookSpec {
    let event: String        // "UserPromptSubmit", "Notification", etc.
    let matcher: String?     // "AskUserQuestion|ExitPlanMode", or nil
    let command: String
    let timeout: Int
}

enum JSONHookMerger {

    // MARK: - Standard Lights hook specs

    static let lightsHookSpecs: [HookSpec] = [
        HookSpec(event: "UserPromptSubmit", matcher: nil,
                 command: lightsCurl("executing"),  timeout: 2000),
        HookSpec(event: "Notification",     matcher: nil,
                 command: lightsCurl("permission"), timeout: 2000),
        HookSpec(event: "Stop",             matcher: nil,
                 command: lightsCurl("idle"),       timeout: 2000),
        HookSpec(event: "PreToolUse",  matcher: "AskUserQuestion|ExitPlanMode",
                 command: lightsCurl("permission"), timeout: 2000),
        HookSpec(event: "PostToolUse", matcher: "AskUserQuestion|ExitPlanMode",
                 command: lightsCurl("executing"),  timeout: 2000),
    ]

    /// Codex uses `PermissionRequest` instead of `Notification`.
    static let codexHookSpecs: [HookSpec] = lightsHookSpecs.map { spec in
        spec.event == "Notification"
            ? HookSpec(event: "PermissionRequest", matcher: spec.matcher,
                       command: spec.command, timeout: spec.timeout)
            : spec
    }

    static let lightsCommandFragments = [
        "9876/executing", "9876/permission", "9876/idle", "9876/off"
    ]

    private static func lightsCurl(_ endpoint: String) -> String {
        "curl -s --max-time 1 http://127.0.0.1:9876/\(endpoint) >/dev/null 2>&1 || true"
    }

    // MARK: - File helpers

    static func backup(_ path: String) throws -> String? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        f.timeZone = TimeZone.current
        let stamp = f.string(from: Date())
        let bak = "\(path).bak-lights-\(stamp)"
        try fm.copyItem(atPath: path, toPath: bak)
        return bak
    }

    static func readJSON(_ path: String) throws -> [String: Any] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return [:] }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        if data.isEmpty { return [:] }
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ToolIntegrationError.invalidJSON(path)
        }
        return dict
    }

    static func writeJSON(_ dict: [String: Any], to path: String) throws {
        let data = try JSONSerialization.data(
            withJSONObject: dict,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        var s = String(data: data, encoding: .utf8) ?? ""
        if !s.hasSuffix("\n") { s += "\n" }
        try s.write(toFile: path, atomically: true, encoding: .utf8)
    }

    // MARK: - Merge

    /// Merge specs into settings["hooks"]. Idempotent (skips duplicate commands).
    static func merge(into settings: inout [String: Any], specs: [HookSpec]) {
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for spec in specs {
            var events = hooks[spec.event] as? [[String: Any]] ?? []

            let alreadyExists = events.contains { entry in
                let arr = entry["hooks"] as? [[String: Any]] ?? []
                return arr.contains { ($0["command"] as? String) == spec.command }
            }
            if alreadyExists { continue }

            let entryIdx = events.firstIndex { entry in
                (entry["matcher"] as? String) == spec.matcher
            }

            let newHook: [String: Any] = [
                "type": "command",
                "command": spec.command,
                "timeout": spec.timeout,
            ]

            if let idx = entryIdx {
                var entry = events[idx]
                var arr = entry["hooks"] as? [[String: Any]] ?? []
                arr.append(newHook)
                entry["hooks"] = arr
                events[idx] = entry
            } else {
                var newEntry: [String: Any] = ["hooks": [newHook]]
                if let m = spec.matcher { newEntry["matcher"] = m }
                events.append(newEntry)
            }
            hooks[spec.event] = events
        }
        settings["hooks"] = hooks
    }

    /// Remove hooks whose command contains any of the given fragments.
    static func removeMatching(_ settings: inout [String: Any], fragments: [String]) {
        guard var hooks = settings["hooks"] as? [String: Any] else { return }
        for (event, value) in hooks {
            guard let events = value as? [[String: Any]] else { continue }
            var newEvents: [[String: Any]] = []
            for entry in events {
                guard let arr = entry["hooks"] as? [[String: Any]] else {
                    newEvents.append(entry); continue
                }
                let kept = arr.filter { hook in
                    let cmd = (hook["command"] as? String) ?? ""
                    return !fragments.contains(where: { cmd.contains($0) })
                }
                if !kept.isEmpty {
                    var newEntry = entry
                    newEntry["hooks"] = kept
                    newEvents.append(newEntry)
                }
            }
            if newEvents.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = newEvents
            }
        }
        if hooks.isEmpty {
            settings.removeValue(forKey: "hooks")
        } else {
            settings["hooks"] = hooks
        }
    }

    /// True if any hook command contains any of the given fragments.
    static func containsAnyHook(_ settings: [String: Any], fragments: [String]) -> Bool {
        guard let hooks = settings["hooks"] as? [String: Any] else { return false }
        for (_, value) in hooks {
            guard let events = value as? [[String: Any]] else { continue }
            for entry in events {
                guard let arr = entry["hooks"] as? [[String: Any]] else { continue }
                for hook in arr {
                    let cmd = (hook["command"] as? String) ?? ""
                    if fragments.contains(where: { cmd.contains($0) }) { return true }
                }
            }
        }
        return false
    }
}
