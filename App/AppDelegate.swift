import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayWindow: OverlayWindow!
    private var renderer: MetalRenderer!
    private var menuBar: MenuBarController!
    private var langManager = LanguageManager()
    private var onboardingController: OnboardingWindowController?
    private var achievementNotifications: AchievementNotificationController?
    private let runDiagnostics = AppRunDiagnostics { message in
        Log.lifecycle.notice("\(message, privacy: .public)")
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        runDiagnostics.recordLaunchAttempt()
        let running = NSRunningApplication.runningApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? ""
        )
        if running.count > 1 {
            runDiagnostics.recordTerminationRequest(.duplicateInstance)
            running.first(where: { $0 != NSRunningApplication.current })?.activate(options: .activateIgnoringOtherApps)
            NSApp.terminate(nil)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        do {
            let preview = try PetPreviewConfiguration.from(arguments: CommandLine.arguments)
            renderer = try MetalRenderer(preview: preview)
        } catch {
            runDiagnostics.recordTerminationRequest(.startupFailure)
            let alert = NSAlert()
            alert.messageText = langManager["brand.could_not_start"]
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        runDiagnostics.markRunning()

        overlayWindow = OverlayWindow()
        let union = OverlayWindow.unionFrame()
        renderer.view.frame = NSRect(origin: .zero, size: union.size)
        renderer.view.autoresizingMask = [.width, .height]
        let vc = NSViewController()
        vc.view = renderer.view
        overlayWindow.contentViewController = vc
        overlayWindow.orderFrontRegardless()

        menuBar = MenuBarController(renderer: renderer, langManager: langManager)

        // Wire achievement toast notifications
        achievementNotifications = AchievementNotificationController(
            manager: renderer.achievementManager, langManager: langManager
        )

        if !renderer.isPreview, !UserDefaults.standard.bool(forKey: "onboarding_completed") {
            onboardingController = OnboardingWindowController(
                renderer: renderer,
                langManager: langManager
            )
            onboardingController?.show()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard let renderer, !renderer.isPreview else { return false }
        if UserDefaults.standard.bool(forKey: "onboarding_completed") {
            menuBar?.showSettings()
        } else {
            if onboardingController == nil {
                onboardingController = OnboardingWindowController(
                    renderer: renderer,
                    langManager: langManager
                )
            }
            onboardingController?.show()
        }
        // The desktop overlay is always visible, so it cannot determine whether
        // the user has a usable settings or welcome window open.
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        renderer?.stop()
        runDiagnostics.finish()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        runDiagnostics.recordTerminationRequest()
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
