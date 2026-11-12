import AppKit
import SwiftUI
import Combine

/// Floating settings panel — appears below the menu bar icon, stays on top.
final class SettingsWindow: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 630),
            styleMask:   [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing:     .buffered,
            defer:       false
        )
        title                          = "PiaoPal"
        titlebarAppearsTransparent     = true
        isMovableByWindowBackground    = true
        level                          = .floating
        isReleasedWhenClosed           = false
        collectionBehavior             = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor                = NSColor.piaCanvas
    }

    override var canBecomeKey: Bool { true }

    func show(relativeTo button: NSStatusBarButton) {
        let screenFrame = button.window?.screen?.frame ?? NSScreen.main?.frame ?? .zero
        let winW = frame.width
        let winH = frame.height

        let btnScreenOrigin = button.window.map {
            button.convert(NSPoint.zero, to: nil)
                .applying(CGAffineTransform(translationX: $0.frame.origin.x,
                                            y: $0.frame.origin.y))
        } ?? NSPoint.zero

        var x = btnScreenOrigin.x + button.bounds.width / 2 - winW / 2
        var y = btnScreenOrigin.y - winH - 4

        x = min(max(x, screenFrame.minX + 8), screenFrame.maxX - winW - 8)
        y = max(y, screenFrame.minY + 8)

        setFrameOrigin(NSPoint(x: x, y: y))
        makeKeyAndOrderFront(nil)
    }
}

/// Wraps the SwiftUI ControlPanel into the NSPanel.
@MainActor
final class SettingsWindowController {
    private let window = SettingsWindow()
    private let updater = Updater()
    private var wrappedController: WrappedWindowController?
    private var marketplaceController: MarketplaceWindowController?
    private var customPetController: CustomPetWindowController?
    private var achievementsController: AchievementsWindowController?
    private var languageCancellable: AnyCancellable?

    init(renderer: MetalRenderer, langManager: LanguageManager) {
        let wrapped      = WrappedWindowController(renderer: renderer, langManager: langManager)
        let customPet    = CustomPetWindowController(renderer: renderer, langManager: langManager)
        let marketplace  = MarketplaceWindowController(
            renderer: renderer,
            langManager: langManager,
            onCreateCustomPet: { customPet.show() }
        )
        let achievements = AchievementsWindowController(manager: renderer.achievementManager, langManager: langManager)
        self.wrappedController      = wrapped
        self.marketplaceController  = marketplace
        self.customPetController    = customPet
        self.achievementsController = achievements

        let view = SettingsView(
            renderer: renderer,
            updater:  updater,
            onShowWrapped:        { wrapped.show() },
            onShowMarketplace:    { marketplace.show() },
            onShowCustomPet:      { customPet.show() },
            onShowAchievements:   { achievements.show() }
        )
        .environmentObject(langManager)
        window.contentView = NSHostingView(rootView: view)
        window.title = langManager.appName
        languageCancellable = langManager.$language
            .receive(on: RunLoop.main)
            .sink { [weak self, weak langManager] _ in
                guard let langManager else { return }
                self?.window.title = langManager.appName
            }
    }

    func show(relativeTo button: NSStatusBarButton? = nil) {
        if window.isVisible {
            window.makeKeyAndOrderFront(nil)
        } else if let button, button.window != nil {
            window.show(relativeTo: button)
        } else {
            window.center()
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func toggle(relativeTo button: NSStatusBarButton) {
        if window.isVisible {
            window.orderOut(nil)
        } else {
            show(relativeTo: button)
        }
    }
}
