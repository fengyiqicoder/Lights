import AppKit

extension Notification.Name {
    static let lightsToggleWindow = Notification.Name("LightsToggleWindow")
    static let lightsShowSetup    = Notification.Name("LightsShowSetup")
    static let lightsRequestOff   = Notification.Name("LightsRequestOff")
    static let lightsSetSize      = Notification.Name("LightsSetSize")
}

final class MenuBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = item.button {
            btn.image = Self.renderStatusIcon()
            btn.imagePosition = .imageOnly
        }
        item.isVisible = true
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        rebuild(menu: menu)
        item.menu = menu
        statusItem = item
        NSLog("[Lights] StatusItem isVisible=\(item.isVisible) length=\(item.length)")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild(menu: menu)
    }

    private func rebuild(menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(item("Show / Hide Window", #selector(actionToggleWindow)))
        menu.addItem(.separator())
        menu.addItem(item("Setup Hooks…", #selector(actionShowSetup)))
        menu.addItem(.separator())

        let sizeItem = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        let sizeMenu = NSMenu()
        let currentSize = LightsSize(rawValue:
            UserDefaults.standard.string(forKey: "lightsSize") ?? "") ?? .large
        for opt in LightsSize.allCases {
            let m = NSMenuItem(title: opt.label,
                               action: #selector(actionSetSize(_:)),
                               keyEquivalent: "")
            m.target = self
            m.representedObject = opt.rawValue
            m.state = (opt == currentSize) ? .on : .off
            sizeMenu.addItem(m)
        }
        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)

        menu.addItem(item("Turn Lights Off", #selector(actionOff)))
        menu.addItem(.separator())
        menu.addItem(item("Quit Lights", #selector(actionQuit), key: "q"))
    }

    private func item(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        i.target = self
        return i
    }

    // MARK: - Actions

    @objc private func actionToggleWindow() {
        NotificationCenter.default.post(name: .lightsToggleWindow, object: nil)
    }

    @objc private func actionShowSetup() {
        NotificationCenter.default.post(name: .lightsShowSetup, object: nil)
    }

    @objc private func actionSetSize(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        UserDefaults.standard.set(raw, forKey: "lightsSize")
        NotificationCenter.default.post(
            name: .lightsSetSize, object: nil, userInfo: ["raw": raw]
        )
    }

    @objc private func actionOff() {
        NotificationCenter.default.post(name: .lightsRequestOff, object: nil)
    }

    @objc private func actionQuit() {
        NSApp.terminate(nil)
    }

    // MARK: - Icon

    static func renderStatusIcon() -> NSImage {
        let size = NSSize(width: 14, height: 18)
        let img = NSImage(size: size)
        img.lockFocus()
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.setShouldAntialias(true)
        ctx.interpolationQuality = .high

        let dotD: CGFloat = 4
        let spacing: CGFloat = 1.6
        let totalH = 3 * dotD + 2 * spacing
        let topCy = (size.height + totalH) / 2 - dotD / 2
        let cx = size.width / 2

        ctx.setFillColor(NSColor.black.cgColor)
        for i in 0..<3 {
            let cy = topCy - CGFloat(i) * (dotD + spacing)
            ctx.fillEllipse(in: CGRect(x: cx - dotD/2, y: cy - dotD/2,
                                       width: dotD, height: dotD))
        }
        img.unlockFocus()
        img.isTemplate = true
        return img
    }
}
