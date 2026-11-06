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
