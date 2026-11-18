import AppKit
import Combine

@main
struct NotificationTests {
    @MainActor
    static func main() {
        let unlocks = PassthroughSubject<Achievement, Never>()
        let display = NSRect(x: -1440, y: 100, width: 1440, height: 900)
        var availableFrame: NSRect?
        var shown: [String] = []
        var dismiss: (() -> Void)?
        let controller = AchievementNotificationController(unlocks: unlocks, screenFrame: {
            availableFrame
        }, present: { achievement, frame, finished in
            precondition(frame == display && dismiss == nil)
            shown.append(achievement.id)
            dismiss = finished
        })
        func deliverEvents() {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        }
        func changeDisplay(to frame: NSRect?) {
            availableFrame = frame
            NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
            deliverEvents()
        }
        func finishToast() {
            let finished = dismiss!
            dismiss = nil
            finished()
        }

        withExtendedLifetime(controller) {
            let items = Array(allAchievements.prefix(3))
            for item in items { unlocks.send(item) }
            deliverEvents()
            precondition(shown.isEmpty, "Unlocks must wait while all displays are disconnected")
            changeDisplay(to: display)
            precondition(shown == [items[0].id])
            changeDisplay(to: display)
            precondition(shown.count == 1, "A display change must not overlap the current toast")

            changeDisplay(to: nil)
            finishToast()
            precondition(shown.count == 1, "Keep the next toast queued when unplugged during dismissal")
            changeDisplay(to: display)
            precondition(shown == [items[0].id, items[1].id])
            finishToast()
            finishToast()
            changeDisplay(to: display)
            precondition(shown == items.map(\.id) && dismiss == nil, "Resume in order and present each toast once")
        }
        print("PASS: achievement toasts survive display loss, resume in order, and never overlap")
    }
}
