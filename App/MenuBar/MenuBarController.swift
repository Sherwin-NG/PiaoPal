import AppKit
import Combine

@MainActor
final class MenuBarController {
    private var statusItem: NSStatusItem!
    private var windowController: SettingsWindowController!
    private weak var renderer: MetalRenderer?
    private let lang: LanguageManager
    private var languageCancellable: AnyCancellable?

    init(renderer: MetalRenderer, langManager: LanguageManager) {
        self.renderer = renderer
        self.lang = langManager
        windowController = SettingsWindowController(renderer: renderer, langManager: langManager)
        setupStatusItem()
        languageCancellable = langManager.$language
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateAccessibilityName() }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let btn = statusItem.button else { return }
        btn.image = NSImage(systemSymbolName: "pawprint.fill",
                            accessibilityDescription: lang.appName)
        btn.imageScaling = .scaleProportionallyDown
        btn.action = #selector(handleClick(_:))
        btn.target = self
        btn.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateAccessibilityName()
    }

    private func updateAccessibilityName() {
        statusItem.button?.setAccessibilityLabel(lang.appName)
        statusItem.button?.toolTip = lang.appName
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            windowController.toggle(relativeTo: sender)
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let laserItem = NSMenuItem(
            title: lang["menu.laser"],
            action: #selector(toggleLaser),
            keyEquivalent: ""
        )
        laserItem.image = NSImage(systemSymbolName: "scope", accessibilityDescription: nil)
        laserItem.target = self
        laserItem.state  = (renderer?.laserActive ?? false) ? .on : .off
        menu.addItem(laserItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: lang["menu.settings"],
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(
            title: lang["settings.quit"],
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        // Temporarily assign menu so the button triggers it, then clear.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func toggleLaser() {
        guard let renderer else { return }
        renderer.setLaserActive(!renderer.laserActive)
    }

    func showSettings() {
        windowController.show(relativeTo: statusItem.button)
    }

    @objc private func openSettings() {
        showSettings()
    }
}
