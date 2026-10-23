import AppKit
import SwiftUI
import Combine

// MARK: – Toast view

private struct AchievementToastView: View {
    @EnvironmentObject var lang: LanguageManager
    let achievement: Achievement

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: achievement.icon).foregroundStyle(Color.piaAccent)
                .font(.system(size: 28))
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(lang["achievements.unlocked"])
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.piaAccent)
                    .tracking(0.5)
                Text(achievement.localizedTitle(using: lang))
                    .font(.callout.bold())
                    .foregroundStyle(Color.piaInk)
                Text(achievement.localizedDescription(using: lang))
                    .font(.caption)
                    .foregroundStyle(Color.piaMuted)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.piaCanvas.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.piaAccent.opacity(0.35), lineWidth: 1)
                )
        )
        .shadow(color: Color.piaInk.opacity(0.04), radius: 8, x: 0, y: 3)
        .frame(width: 300, height: 72)
    }
}

// MARK: – Controller

/// Queues achievement toasts and shows them one at a time, sliding up from the bottom of the screen.
@MainActor
final class AchievementNotificationController {
    private var queue: [Achievement] = []
    private var isShowing = false
    private var activePanel: NSPanel?
    private var cancellable: AnyCancellable?
    private let langManager: LanguageManager

    init(manager: AchievementManager, langManager: LanguageManager) {
        self.langManager = langManager
        cancellable = manager.unlockPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] a in self?.enqueue(a) }
    }

    private func enqueue(_ a: Achievement) {
        queue.append(a)
        if !isShowing { showNext() }
    }

    private func showNext() {
        guard !queue.isEmpty else { isShowing = false; return }
        isShowing = true
        let achievement = queue.removeFirst()

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let w: CGFloat = 300
        let h: CGFloat = 72
        let x = screen.frame.midX - w / 2
        let hiddenY  = screen.frame.minY - h - 16
        let visibleY = screen.frame.minY + 28

        let hostView = NSHostingView(
            rootView: AchievementToastView(achievement: achievement)
                .environmentObject(langManager)
                .colorScheme(.light)
        )
        hostView.layer?.backgroundColor = CGColor.clear

        let panel = NSPanel(
            contentRect: NSRect(x: x, y: hiddenY, width: w, height: h),
            styleMask:   [.borderless, .nonactivatingPanel],
            backing:     .buffered,
            defer:       false
        )
        panel.backgroundColor        = .clear
        panel.isOpaque               = false
        panel.hasShadow              = false
        panel.level                  = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)) + 2)
        panel.collectionBehavior     = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.ignoresMouseEvents     = true
        panel.isReleasedWhenClosed   = false
        panel.contentView            = hostView
        panel.orderFrontRegardless()
        activePanel = panel

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.38
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(NSRect(x: x, y: visibleY, width: w, height: h), display: true)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.6) { [weak self] in
            guard self?.activePanel == panel else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.28
                panel.animator().setFrame(NSRect(x: x, y: hiddenY, width: w, height: h), display: true)
                panel.animator().alphaValue = 0
            }, completionHandler: {
                Task { @MainActor [weak self] in
                    panel.orderOut(nil)
                    self?.showNext()
                }
            })
        }
    }
}
