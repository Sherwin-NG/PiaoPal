import CoreGraphics
import Foundation
import os.log

enum Log {
    static let engine  = Logger(subsystem: "io.github.sherwinng.PiaoPal", category: "engine")
    static let render  = Logger(subsystem: "io.github.sherwinng.PiaoPal", category: "render")
    static let input   = Logger(subsystem: "io.github.sherwinng.PiaoPal", category: "input")
    static let skin    = Logger(subsystem: "io.github.sherwinng.PiaoPal", category: "skin")
    static let store   = Logger(subsystem: "io.github.sherwinng.PiaoPal", category: "store")
    static let lifecycle = Logger(subsystem: "io.github.sherwinng.PiaoPal", category: "lifecycle")
}

/// Local diagnostics only. AppDelegate calls these methods on the main thread.
final class AppRunDiagnostics {
    enum TerminationReason: String {
        case requested = "quit_requested_user_or_system"
        case duplicateInstance = "duplicate_instance"
        case startupFailure = "startup_failure"
    }

    static let activeRunKey = "diagnostics_active_run_v1"

    private let defaults: UserDefaults
    private let version: String
    private let processID: Int32
    private let sessionID: String
    private let log: (String) -> Void
    private var terminationReason: TerminationReason?
    private var ownsRunMarker = false
    private var hasFinished = false

    init(
        defaults: UserDefaults = .standard,
        version: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
        processID: Int32 = ProcessInfo.processInfo.processIdentifier,
        sessionID: String = UUID().uuidString,
        log: @escaping (String) -> Void
    ) {
        self.defaults = defaults
        self.version = version
        self.processID = processID
        self.sessionID = sessionID
        self.log = log
    }

    func recordLaunchAttempt() {
        record("launch_attempt")
    }

    /// Call only after duplicate-instance detection and successful renderer setup.
    /// Failed/rejected launches must not replace the existing run's marker.
    func markRunning() {
        guard terminationReason == nil, !ownsRunMarker, !hasFinished else { return }

        if let previous = defaults.dictionary(forKey: Self.activeRunKey) {
            let previousPID = previous["pid"] as? Int ?? 0
            let previousVersion = previous["version"] as? String ?? "unknown"
            record("previous_run_missing_normal_exit previous_pid=\(previousPID) previous_version=\(previousVersion); possible causes include force quit or power loss")
        }

        defaults.set([
            "session": sessionID,
            "pid": Int(processID),
            "version": version,
        ], forKey: Self.activeRunKey)
        ownsRunMarker = true
        record("running")
    }

    func recordTerminationRequest(_ reason: TerminationReason = .requested) {
        guard terminationReason == nil, !hasFinished else { return }
        terminationReason = reason
        record("termination_requested reason=\(reason.rawValue)")
    }

    /// Call after renderer cleanup has completed. A second process must never
    /// clear a marker written by the process that is actually running.
    func finish() {
        guard !hasFinished else { return }
        hasFinished = true
        if ownsRunMarker {
            let storedSession = defaults.dictionary(forKey: Self.activeRunKey)?["session"] as? String
            if storedSession == sessionID {
                defaults.removeObject(forKey: Self.activeRunKey)
            } else {
                record("run_marker_preserved reason=owned_by_another_session")
            }
            ownsRunMarker = false
        }
        record("termination_completed reason=\(terminationReason?.rawValue ?? "application_termination")")
    }

    private func record(_ event: String) {
        log("\(event) pid=\(processID) version=\(version) session=\(sessionID)")
    }
}

/// Decides whether this launch must exit because another live copy is already running.
/// `NSRunningApplication.runningApplications(withBundleIdentifier:)` also returns this
/// process and apps that have terminated but not yet left the list. Treating either as
/// a duplicate calls `NSApp.terminate` and the only live copy disappears.
struct LaunchInstancePolicy {
    struct Peer {
        var processID: Int32
        var isTerminated: Bool
    }

    static func shouldExitAsDuplicate(
        bundleIdentifier: String?,
        currentProcessID: Int32,
        peers: [Peer]
    ) -> Bool {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return false }
        return peers.contains { $0.processID != currentProcessID && !$0.isTerminated }
    }
}

/// AppKit raises an uncaught exception for non-finite, empty, or enormous window frames,
/// and CAMetalLayer does the same for drawable sizes past the GPU limit. Both abort the
/// process. Ordinary multi-monitor frames, including negative origins, stay unchanged.
enum DesktopFramePolicy {
    static let maximumPixels: CGFloat = 16_384
    static let maximumOriginMagnitude: CGFloat = 1_000_000

    static func isSafeWindowFrame(_ frame: CGRect, scale: CGFloat) -> Bool {
        guard frame.origin.x.isFinite, frame.origin.y.isFinite,
              frame.size.width.isFinite, frame.size.height.isFinite,
              scale.isFinite, scale > 0, scale <= 8,
              abs(frame.origin.x) <= maximumOriginMagnitude,
              abs(frame.origin.y) <= maximumOriginMagnitude,
              frame.width > 1, frame.height > 1,
              frame.width <= maximumPixels, frame.height <= maximumPixels else { return false }
        let pixelWidth = frame.width * scale
        let pixelHeight = frame.height * scale
        return pixelWidth.isFinite && pixelHeight.isFinite
            && pixelWidth <= maximumPixels && pixelHeight <= maximumPixels
    }

    static func safeDrawablePixelSize(
        pointWidth: CGFloat, pointHeight: CGFloat, scale: CGFloat, maximumPixels: Int
    ) -> CGSize? {
        guard pointWidth.isFinite, pointHeight.isFinite, scale.isFinite, scale > 0,
              maximumPixels >= 64 else { return nil }
        let width = pointWidth * scale
        let height = pointHeight * scale
        guard width.isFinite, height.isFinite, width >= 1, height >= 1,
              width <= CGFloat(maximumPixels), height <= CGFloat(maximumPixels) else { return nil }
        return CGSize(width: width, height: height)
    }
}
