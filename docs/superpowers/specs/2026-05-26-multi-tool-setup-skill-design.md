# Lights 多工具 Hook 检测 + Skill 包 设计

- **日期**: 2026-05-26
- **状态**: 实施中（Phase A 已落地：icon + menu bar app；Phase B 进行中：multi-tool + Setup UI）
- **基线**: Lights v0.1（浮动交通灯 + HTTP 9876 + Claude Code 五 hook 已可用，包含 PreToolUse/PostToolUse for AskUserQuestion）

## 1. 目标

让 Lights 不再依赖用户手动改 `settings.json`：

1. App 启动时自动检测系统上有哪些 AI coding 工具，以及它们是否已经接好 Lights hook
2. 缺的工具弹出 Setup 面板让用户**一键安装** hook（直接改对应工具的 config）
3. 同步发布一个 `lights-hooks` skill，让没装 macOS app 的人也能从 skills.sh 走 `npx skillsadd fengyiqicoder/lights-hooks` 装
4. App 本身做成 **menu bar agent**：自带应用图标、不在 Dock 显示，更贴合"常驻状态指示器"的角色

## 2. Non-goals (v1 不做)

- v1 真实做 **Claude Code + Codex CLI**；Goose / OpenCode 只在 UI 占位（Codex 后期调研发现有几乎同款 hooks）
- 不做远程更新检查、telemetry、登录态
- 不做多 session 状态聚合（沿用 last-write-wins）
- 不做卸载向导（Uninstall 按钮够用，不另开流程）
- Skill 仅针对 Claude Code 写，不在 SKILL.md 里写多工具分支（避免 AI 在不该跑的地方乱跑）

## 3. 架构

```
                     macOS menu bar
        ┌──────────────────────── ⏺⏺⏺ ◀── NSStatusItem (3 dots)
        │                                ┌─ Show / Hide Window
        │                                ├─ Setup Hooks…
   ┌────┴───────────────────────────┐    ├─ Size ▸ (S/M/L)
   │   Lights.app  (LSUIElement)    │    ├─ Turn Lights Off
   │   ── no Dock icon ──            │    └─ Quit Lights
   │                                 │
   │   ┌──────────┐    ┌──────────┐  │
   │   │ 浮动灯    │    │ SetupView│  │
   │   │ (always  │◄──┤  Sheet   │  │
   │   │  on top) │    └──────────┘  │
   │   │  right ▸ │     ▲   │        │
   │   │   Setup… │─────┘   │        │
   │   │   Size ▸ │         │        │
   │   │   Off    │         │ writes │
   │   └──────────┘         ▼        │
   │        ▲      ┌────────────────┐│
   │   curl │      │ JSON / TOML    ││
   │        │      │ merge engine   ││
   └────────┼──────┴────────┬───────┘│
            │               │        │
   ┌────────┴────┐     ┌────┴──────┐ │
   │ HTTP 9876   │     │ ~/.claude │ │
   │ (existing)  │     │ ~/.codex  │ │
   └─────────────┘     └───────────┘ │
                                     │
            ┌────────────────────────┘
            ▼
   ┌─────────────────────────────────────┐
   │  skill/SKILL.md (Claude Code only)  │
   │  pushed to fengyiqicoder/lights-hooks│
   │  users run npx skillsadd ...        │
   └─────────────────────────────────────┘
```

## 3.1 App 形态：menu bar agent

- `LSUIElement = true` in Info.plist + `NSApp.setActivationPolicy(.accessory)` 双保险，移除 Dock 图标
- 新增 `MenuBarController` 拥有 `NSStatusItem`，菜单镜像了浮动窗右键所有动作 + 新增 "Show / Hide Window"
- App icon 是程序生成的 1024×1024 squircle（深色渐变背景 + 三个发光交通灯），通过 `tools/render-icon.swift` 渲染 PNG → `iconutil` 打包成 `Resources/AppIcon.icns`，由 `build-app.sh` 自动构建
- ⚠️ **已知 macOS 限制**：MacBook Pro notch + 用户已有较多 menu bar 项时，新增的 status item 可能被挤到 notch 后面不可见。此时浮动窗口右键菜单提供等价入口，功能不丢，只是图标隐藏

## 4. 组件

### 4.1 `ToolIntegration` protocol — 多工具插槽

新文件 `Sources/Lights/ToolIntegration.swift`：

```swift
enum SupportLevel {
    case events           // 真有事件 hook，灯实时
    case reminderOnly     // 只能让 AI 自觉调（不可靠，v1 不暴露）
    case notSupported     // 工具没事件 hook
    case comingSoon       // 我们还没实做
}

enum InstallStatus: Equatable {
    case toolNotInstalled
    case toolPresentHookMissing
    case configured
    case unknown(String)        // 检测出错，附原因
}

protocol ToolIntegration {
    var id: String { get }              // "claude-code"
    var displayName: String { get }     // "Claude Code"
    var supportLevel: SupportLevel { get }
    var statusBlurb: String { get }     // 给 UI 显示一行说明

    func detectStatus() -> InstallStatus
    func install() throws               // 修改 config 文件
    func uninstall() throws             // 移除 hook
}
```

### 4.2 `ClaudeCodeIntegration` — v1 唯一实做

新文件 `Sources/Lights/ClaudeCodeIntegration.swift`。

**检测 `detectStatus()`：**
1. 文件 `~/.claude/settings.json` 不存在且 `which claude` 失败 → `.toolNotInstalled`
2. 文件存在，读 JSON，扫描 `hooks` 下所有 `command` 字段
3. 若任一字段含 `9876/executing` 子串 → `.configured`
4. 否则 → `.toolPresentHookMissing`

**安装 `install()`：**
1. 备份 `settings.json` 到 `settings.json.bak-lights-YYYYMMDD-HHMMSS`
2. 解析 JSON 为 `[String: Any]` (用 `JSONSerialization`)
3. 对四个事件 `UserPromptSubmit` / `Notification` / `Stop` / `PreToolUse(AskUserQuestion|ExitPlanMode)` / `PostToolUse(AskUserQuestion|ExitPlanMode)`：
   - **JSON merge 规则**：见 §5
4. 写回，2 空格缩进，末尾换行

**卸载 `uninstall()`：**
1. 备份
2. 扫描所有 hook command，删除含 `9876/(executing|permission|idle|off)` 的项
3. 删空的 `hooks` 数组（清掉副作用残留）
4. 写回

### 4.3 占位 integrations（Goose / OpenCode）

| File | supportLevel | statusBlurb |
|---|---|---|
| `GooseIntegration.swift` | `.comingSoon` | "未找到事件 hook 文档" |
| `OpenCodeIntegration.swift` | `.notSupported` | "OpenCode 暂无事件 hook" |

`install()` / `uninstall()` 抛 `NotImplementedError`，UI 层把按钮 disable。

### 4.3a `CodexIntegration` — v1 第二个真实做

Codex CLI 文档（developers.openai.com/codex）确认有几乎和 Claude Code 同款的 lifecycle hooks。

**配置文件：**
- `~/.codex/hooks.json` — 主要 hook 定义（同款 JSON schema，复用 §5 merge 引擎）
- `~/.codex/config.toml` — 需含 `features.hooks = true` 才启用 hook 子系统

**事件映射：**
| Codex 事件 | 等价 Claude Code | Lights 端点 |
|---|---|---|
| `UserPromptSubmit` | 同名 | `/executing` |
| `PermissionRequest` | `Notification` | `/permission` |
| `Stop` | 同名 | `/idle` |
| `PreToolUse` (matcher: 待定) | 同名 | `/permission`（如有"询问用户"工具） |
| `PostToolUse` (同) | 同名 | `/executing` |

**检测 `detectStatus()`：**
1. `~/.codex/` 不存在且 `which codex` 失败 → `.toolNotInstalled`
2. 读 `~/.codex/hooks.json`，扫描含 `9876/executing` → `.configured`
3. 否则 → `.toolPresentHookMissing`

**安装 `install()`：**
1. 备份 hooks.json 和 config.toml（若存在）
2. JSON merge hook 项进 hooks.json（复用 §5 算法）
3. 读 config.toml；若没有 `features.hooks = true` 这一行 → 在末尾追加（朴素文本追加，不强制 TOML 解析，避免引入依赖）
4. 写回

**卸载 `uninstall()`：**
1. 备份
2. 从 hooks.json 删 9876 hook 项
3. **不**动 `features.hooks = true`（用户可能给其他工具用）

### 4.4 `SetupView.swift` — SwiftUI 面板

布局（ASCII）：

```
┌──────────────────────────────────────────────────────┐
│  Lights Setup                                    [×] │
├──────────────────────────────────────────────────────┤
│  Connect Lights to your AI coding tools.             │
│  Lights must be running for hooks to reach it.       │
│                                                      │
│  ┌─────────────────────────────────────────────────┐ │
│  │ 🟢 Claude Code          Configured  [Uninstall]│ │
│  │ ⚪ Goose                Coming soon — v2       │ │
│  │ ⚪ Codex CLI            Coming soon — v2       │ │
│  │ ⚫ OpenCode             No event hooks         │ │
│  └─────────────────────────────────────────────────┘ │
│                                                      │
│  ⚠ Backups saved as settings.json.bak-lights-…       │
│                                                      │
│                                  [Refresh] [Done]    │
└──────────────────────────────────────────────────────┘
```

每行：状态徽章 + 工具名 + statusBlurb + 操作按钮。
按钮逻辑：
- `.toolNotInstalled` → 显示 "Not installed"，无按钮
- `.toolPresentHookMissing` → `[Install]`
- `.configured` → `[Uninstall]`
- `.comingSoon` / `.notSupported` → 按钮 disabled，灰
- `.unknown(let why)` → `[Retry]`，hover 提示原因

`[Refresh]` 重新跑所有 `detectStatus()`。

实现细节：
- `@ObservableObject` 的 `SetupManager` 持 `[ToolIntegration]`，每个工具一个 `@Published var status: InstallStatus`
- Button 触发 `install()` / `uninstall()` 后立刻 re-detect
- 异常用 NSAlert 弹错误

### 4.5 `SetupManager.swift` — 首次启动判定 + 注册表

```swift
final class SetupManager: ObservableObject {
    static let shared = SetupManager()
    @Published var tools: [ToolIntegrationState]   // wraps integration + observed status

    func refreshAll()
    func install(_ id: String) throws
    func uninstall(_ id: String) throws
}
```

首次启动判定：
- 检查 `~/Library/Application Support/Lights/seen-setup.flag`
- 不存在 → 主动调 `applicationDidFinishLaunching` 末尾 `SetupManager.shared.showSetupSheet()`
- 完成关闭后写入 flag

### 4.6 `main.swift` 改动

- AppDelegate：
  - launch 末尾按 §4.5 决定是否自弹 Setup sheet
- ContextMenu (ContentView)：
  - 现有 "Size" 子菜单和 "Off" / "Quit" 之间插一项 "Setup Hooks…"
  - 点击 → `NotificationCenter.post(.lightsShowSetup, …)`，AppDelegate 监听并弹 sheet

### 4.7 `skill/SKILL.md` — skills.sh 入口

```yaml
---
name: lights-hooks
description: |
  Install Lights traffic-light status hooks into Claude Code's settings.json.
  Lights is a macOS traffic-light overlay showing AI activity (red=executing,
  yellow=needs input, green=idle).
  Use this skill when the user says "set up Lights hooks", "connect Lights to
  Claude Code", "install lights skill", or installs Lights and asks how to
  hook it up.
---

# Install Lights Hooks for Claude Code

## Pre-flight

Verify Lights is running and reachable:

```bash
curl -s --max-time 1 http://127.0.0.1:9876/status
```

If this fails:
- Tell the user: "Lights app isn't running. Launch /Applications/Lights.app
  (or open Lights.app from the project), then re-invoke this skill."
- STOP. Do not proceed.

## Install steps

1. Back up `~/.claude/settings.json` to
   `~/.claude/settings.json.bak-lights-$(date +%Y%m%d-%H%M%S)`
2. Read the JSON. If `hooks` key missing, create `{}`.
3. For each of the following events, **add or merge** an entry; **don't clobber
   existing hooks**:

| Event | Matcher | Command |
|---|---|---|
| UserPromptSubmit | (none) | `curl -s --max-time 1 http://127.0.0.1:9876/executing >/dev/null 2>&1 || true` |
| Notification | (none) | `... /permission ...` |
| Stop | (none) | `... /idle ...` |
| PreToolUse | `AskUserQuestion\|ExitPlanMode` | `... /permission ...` |
| PostToolUse | `AskUserQuestion\|ExitPlanMode` | `... /executing ...` |

All hooks: `type: "command"`, `timeout: 2000`.

4. Write JSON back with 2-space indent.
5. Verify by `curl -s http://127.0.0.1:9876/status` and reporting result.

## Idempotency

Before adding any hook, scan existing commands for `9876/<endpoint>` —
if already present for that endpoint, skip; don't duplicate.

## Uninstall (`/lights-hooks-uninstall`)

Optional alternate trigger. Same backup, then remove any hook whose command
contains `9876/(executing|permission|idle|off)`.
```

## 5. JSON Merge 规则（关键，避免破坏用户已有 hooks）

输入：`settings.json` 已有的 `hooks` 字典 + 新 hook spec `(event, matcher?, command)`

```
def merge_hook(settings, event, matcher, command):
    events = settings.setdefault("hooks", {}).setdefault(event, [])

    # 1. dedupe: 如果 command 已经存在，啥也不干
    for entry in events:
        for h in entry.get("hooks", []):
            if h.get("command") == command:
                return

    # 2. 找匹配 matcher 的 entry
    target = None
    for entry in events:
        if entry.get("matcher") == matcher:   # None == None 也算匹配
            target = entry
            break

    # 3. 找到则追加，没找到新建 entry
    new_hook = {"type": "command", "command": command, "timeout": 2000}
    if target:
        target.setdefault("hooks", []).append(new_hook)
    else:
        new_entry = {"hooks": [new_hook]}
        if matcher: new_entry["matcher"] = matcher
        events.append(new_entry)
```

**关键不变量**：
- 不动现有 `command`
- 不动现有 entry 的 `matcher` 字段
- 不重复添加同一 command
- 不重排 entry 顺序（保持 diff 小）

Uninstall 是 merge 的反向：扫描 entries → 删 hook → 删空 entry。

## 6. 边界与错误处理

| 场景 | 行为 |
|---|---|
| `settings.json` 是损坏 JSON | UI 弹 alert，列出文件路径，用户自查；不擅自重写 |
| `~/.claude/` 不存在 | 当 `.toolNotInstalled` |
| 写文件无权限 | NSAlert + 引导终端命令手装 |
| Lights 未运行（用户在终端用 hook） | curl 超时 1s，hook `|| true` 静默 |
| 多 Claude 会话同时跑 | 沿用 last-write-wins (已设计) |
| `which goose` 检测失败但 Goose 已装 | Refresh 按钮兜底；v2 加 `~/.config/goose/` 路径检测 |
| 用户已手动加过 hook | merge 算法 dedupe 跳过，不重复 |

## 7. 测试方案

**单元测试**（v1 暂不引入 XCTest target，手动验证）：
- JSON merge：构造 5 种 fixtures（空 hooks / 已有相同 hook / 已有不同 matcher / 已有同 matcher 不同 command / 损坏 JSON）
- 卸载：装了再卸，文件应回到原状（除 backup 文件外字节级一致）

**集成验证步骤**：
1. 备份当前 settings.json 到旁路
2. 删掉 settings.json 里的 9876 hooks（模拟"未安装"状态）
3. 启动 Lights → 首次弹 Setup → 看到 Claude Code 行 `[Install]`
4. 点 Install → 重启 Claude Code → curl 测端点 → 灯响应
5. 回 Setup → 点 Uninstall → settings.json diff 应是干净的反向

## 8. 文件改动清单

新增（Phase A 已落地）：
- `tools/render-icon.swift` ✅
- `Resources/AppIcon.icns` ✅（构建产物）
- `Sources/Lights/MenuBarController.swift` ✅

新增（Phase B 待做）：
- `Sources/Lights/ToolIntegration.swift`
- `Sources/Lights/ClaudeCodeIntegration.swift`
- `Sources/Lights/CodexIntegration.swift`
- `Sources/Lights/GooseIntegration.swift`
- `Sources/Lights/OpenCodeIntegration.swift`
- `Sources/Lights/JSONHookMerger.swift`（§5 算法独立成文件）
- `Sources/Lights/SetupView.swift`
- `Sources/Lights/SetupManager.swift`
- `skill/SKILL.md`
- `skill/README.md`

已改（Phase A）：
- `Sources/Lights/main.swift` ✅
  - `setActivationPolicy(.accessory)`
  - 创建 MenuBarController 并 install()
  - 加 `.lightsToggleWindow` / `.lightsShowSetup` / `.lightsRequestOff` 通知监听
  - 右键菜单加 "Setup Hooks…"（目前占位日志）
- `Resources/Info.plist` ✅: `LSUIElement=true`, `CFBundleIconFile=AppIcon`
- `build-app.sh` ✅: 自动渲染 icon + 复制 .icns 到 bundle

待改（Phase B）：
- `Sources/Lights/main.swift`
  - AppDelegate launch 末尾按 seen-setup.flag 决定是否自弹 SetupView sheet
  - `.lightsShowSetup` 监听从占位日志变成真打开 sheet

## 9. 发布 skill 仓库（手动一次性步骤，不在代码内）

实现完成后，用户手动：
```bash
cd /Users/fengyq/Desktop/Lights/skill
git init && git add . && git commit -m "lights-hooks v1"
gh repo create fengyiqicoder/lights-hooks --public --source=. --push
```

然后 `npx skillsadd fengyiqicoder/lights-hooks` 即可工作。

## 10. 未来工作（v2+，不在本 spec 范围）

- Goose / Codex CLI 真实做（待两家 hooks API 稳定）
- 多 session 聚合（带 session-id 的端点 + per-session 状态机）
- menu bar 镜像图标
- 灯主题 / palette 自定义
- 自动检查 Lights 新版本

---

**待审阅项**：你看完后告诉我哪里要改、哪里要砍、哪里要补，再进入 writing-plans 拆任务。
