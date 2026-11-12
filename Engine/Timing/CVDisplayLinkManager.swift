import CoreGraphics
import CoreVideo
import Foundation

/// Drives the render loop via CVDisplayLink.
/// The callback fires on a high-priority display thread, not the main thread.
/// It only records a timestamp and hops to the main queue. AppKit and Metal
/// drawable work happens on main, after this callback returns.
final class CVDisplayLinkManager: NSObject {
    private final class ReconfigTarget {
        weak var manager: CVDisplayLinkManager?
    }

    private var displayLink: CVDisplayLink?
    private var callback: ((Double) -> Void)?
    private var lastTimestamp: CVTimeStamp?
    private let lock = NSLock()
    private var stopped = true
    private var pendingDt: Double = 0
    private var frameScheduled = false
    private var displaysChanging = false
    private var reconfigDepth = 0
    private var reconfigTarget: ReconfigTarget?
    /// Main-thread hook so the renderer can refresh screen geometry between
    /// display-link generations. Never touches AppKit from the link thread.
    var onDisplaysChanged: (() -> Void)?

    private static let reconfigCallback: CGDisplayReconfigurationCallBack = { _, flags, user in
        guard let user else { return }
        let target = Unmanaged<CVDisplayLinkManager.ReconfigTarget>.fromOpaque(user).takeUnretainedValue()
        target.manager?.handleDisplayReconfiguration(flags)
    }

    var isRunning: Bool {
        lock.lock()
        let link = displayLink
        lock.unlock()
        guard let link else { return false }
        return CVDisplayLinkIsRunning(link)
    }

    /// `tick` is invoked on the main thread and receives delta-time in seconds.
    func start(tick: @escaping (Double) -> Void) {
        lock.lock()
        callback = tick
        stopped = false
        lock.unlock()
        installReconfigObserver()
        replaceLink()
        startLink()
        Log.engine.info("CVDisplayLink started")
    }

    func stop() {
        lock.lock()
        stopped = true
        callback = nil
        onDisplaysChanged = nil
        pendingDt = 0
        frameScheduled = false
        displaysChanging = false
        let link = displayLink
        displayLink = nil
        lock.unlock()
        if let link, CVDisplayLinkIsRunning(link) {
            CVDisplayLinkStop(link)
        }
        removeReconfigObserver()
    }

    /// Stop callbacks before a display configuration changes. The output handler
    /// can fault if it runs against a display that is mid-removal.
    func suspendForDisplayChange() {
        lock.lock()
        displaysChanging = true
        let link = displayLink
        lock.unlock()
        if let link, CVDisplayLinkIsRunning(link) {
            CVDisplayLinkStop(link)
        }
    }

    /// Recreate the link after the configuration settles. A no-op once `stop` ran,
    /// so a removed Metal device cannot be drawn again.
    func resumeAfterDisplayChange() {
        lock.lock()
        let isStopped = stopped
        let link = displayLink
        if !isStopped { displaysChanging = false }
        let running = link.map { CVDisplayLinkIsRunning($0) } ?? false
        lock.unlock()
        guard !isStopped else { return }
        if running { return }
        replaceLink()
        startLink()
    }

    deinit { stop() }

    private func installReconfigObserver() {
        guard reconfigTarget == nil else { return }
        let target = ReconfigTarget()
        target.manager = self
        reconfigTarget = target
        CGDisplayRegisterReconfigurationCallback(
            Self.reconfigCallback,
            Unmanaged.passUnretained(target).toOpaque()
        )
    }

    private func removeReconfigObserver() {
        guard let target = reconfigTarget else { return }
        target.manager = nil
        reconfigTarget = nil
        CGDisplayRemoveReconfigurationCallback(
            Self.reconfigCallback,
            Unmanaged.passUnretained(target).toOpaque()
        )
    }

    private func handleDisplayReconfiguration(_ flags: CGDisplayChangeSummaryFlags) {
        if flags.contains(.beginConfigurationFlag) {
            lock.lock()
            reconfigDepth += 1
            let first = reconfigDepth == 1
            lock.unlock()
            if first { suspendForDisplayChange() }
            return
        }
        lock.lock()
        reconfigDepth = max(0, reconfigDepth - 1)
        let settled = reconfigDepth == 0
        lock.unlock()
        guard settled else { return }
        // The renderer decides whether to resume. Waking the link while the
        // panel is asleep just faults the next drawable.
        DispatchQueue.main.async { [weak self] in
            self?.onDisplaysChanged?()
        }
    }

    private func replaceLink() {
        lock.lock()
        let old = displayLink
        displayLink = nil
        let isStopped = stopped
        lock.unlock()
        if let old, CVDisplayLinkIsRunning(old) {
            // Stop returns only after the output handler does, so lastTimestamp
            // is no longer being written from the display thread.
            CVDisplayLinkStop(old)
        }
        lastTimestamp = nil
        guard !isStopped else { return }
        var created: CVDisplayLink?
        guard CVDisplayLinkCreateWithActiveCGDisplays(&created) == kCVReturnSuccess,
              let created else {
            Log.engine.error("Failed to create CVDisplayLink")
            return
        }
        CVDisplayLinkSetOutputHandler(created) { [weak self] _, inNow, _, _, _ in
            autoreleasepool { self?.handleOutput(inNow.pointee) }
            return kCVReturnSuccess
        }
        lock.lock()
        if stopped {
            lock.unlock()
            return
        }
        displayLink = created
        lock.unlock()
    }

    private func startLink() {
        lock.lock()
        let link = displayLink
        let isStopped = stopped || displaysChanging
        lock.unlock()
        guard let link, !isStopped, !CVDisplayLinkIsRunning(link) else { return }
        CVDisplayLinkStart(link)
        lock.lock()
        let shouldStop = stopped || displaysChanging
        lock.unlock()
        if shouldStop, CVDisplayLinkIsRunning(link) {
            CVDisplayLinkStop(link)
        }
    }

    private func handleOutput(_ now: CVTimeStamp) {
        let dt = computeDt(now)
        lock.lock()
        let shouldSchedule = !stopped && callback != nil
        var needsHop = false
        if shouldSchedule {
            pendingDt = min(0.25, pendingDt + dt)
            needsHop = !frameScheduled
            frameScheduled = true
        }
        lock.unlock()
        guard needsHop else { return }
        DispatchQueue.main.async { [weak self] in self?.drainOnMain() }
    }

    private func drainOnMain() {
        lock.lock()
        let dt = pendingDt
        let tick = callback
        let skip = stopped || displaysChanging
        pendingDt = 0
        frameScheduled = false
        lock.unlock()
        guard !skip, let tick else { return }
        autoreleasepool { tick(dt) }
    }

    // Returns dt in seconds, capped to avoid spiral-of-death.
    private func computeDt(_ now: CVTimeStamp) -> Double {
        defer { lastTimestamp = now }
        guard let last = lastTimestamp,
              now.videoTimeScale > 0, now.videoTimeScale == last.videoTimeScale,
              now.videoTime >= last.videoTime else { return 1.0 / 120.0 }
        let delta = (Double(now.videoTime) - Double(last.videoTime))
            / Double(now.videoTimeScale)
        return delta.isFinite && delta > 0 ? min(delta, 0.1) : 1.0 / 120.0
    }
}
