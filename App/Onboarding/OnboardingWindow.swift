import AppKit
import SwiftUI

// MARK: – Window

final class OnboardingWindow: NSWindow {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 540),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        titlebarAppearsTransparent = true
        titleVisibility            = .hidden
        isMovableByWindowBackground = true
        backgroundColor            = NSColor.piaCanvas
        isReleasedWhenClosed       = false
        level                      = .floating
    }

    override var canBecomeKey: Bool { true }
}

// MARK: – Controller

@MainActor
final class OnboardingWindowController {
    private let window = OnboardingWindow()

    init(renderer: MetalRenderer, langManager: LanguageManager) {
        let view = OnboardingView(renderer: renderer, onFinish: { [weak self] in
            self?.finish()
        })
        .environmentObject(langManager)

        window.contentView = NSHostingView(rootView: view)
    }

    func show() {
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: "onboarding_completed")
        if UserDefaults.standard.string(forKey: "adoption_date") == nil {
            UserDefaults.standard.set(ISO8601DateFormatter().string(from: Date()), forKey: "adoption_date")
        }
        window.close()
    }
}
