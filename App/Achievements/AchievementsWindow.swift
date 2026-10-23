import AppKit
import SwiftUI
import Combine

final class AchievementsWindow: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 540),
            styleMask:   [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing:     .buffered,
            defer:       false
        )
        title                      = "Achievements"
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        level                      = .floating
        isReleasedWhenClosed       = false
        collectionBehavior         = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor            = NSColor.piaCanvas
    }

    override var canBecomeKey: Bool { true }

    func show() {
        if let screen = NSScreen.main {
            let x = screen.frame.midX - frame.width / 2
            let y = screen.frame.midY - frame.height / 2
            setFrameOrigin(NSPoint(x: x, y: y))
        }
        makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class AchievementsWindowController {
    private let window: AchievementsWindow
    private var languageCancellable: AnyCancellable?

    init(manager: AchievementManager, langManager: LanguageManager) {
        window = AchievementsWindow()
        let view = AchievementsView(manager: manager)
            .environmentObject(langManager)
        window.contentView = NSHostingView(rootView: view)
        window.title = langManager["achievements.windowTitle"]
        languageCancellable = langManager.$language
            .receive(on: RunLoop.main)
            .sink { [weak self, weak langManager] _ in
                guard let langManager else { return }
                self?.window.title = langManager["achievements.windowTitle"]
            }
    }

    func show() {
        if window.isVisible {
            window.orderFront(nil)
        } else {
            window.show()
        }
    }
}
