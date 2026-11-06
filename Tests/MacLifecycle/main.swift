import Foundation

let suite = "PiaoPal.QA.RunDiagnostics.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
var logs: [String] = []
var passed = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
    passed += 1
    print("PASS \(message)")
}
func make(_ session: String, pid: Int32 = 123) -> AppRunDiagnostics {
    return AppRunDiagnostics(defaults: defaults, version: "0.1.0", processID: pid, sessionID: session) { logs.append($0) }
}
func storedSession() -> String? {
    return defaults.dictionary(forKey: AppRunDiagnostics.activeRunKey)?["session"] as? String
}
func reset() {
    defaults.removePersistentDomain(forName: suite)
    logs.removeAll()
}

let normal = make("normal")
normal.recordLaunchAttempt()
check(storedSession() == nil, "launch attempt alone does not claim marker")
check(logs.first?.contains("pid=123 version=0.1.0 session=normal") == true, "launch records pid/version/session")
normal.markRunning()
check(storedSession() == "normal", "successful startup claims marker")
normal.recordTerminationRequest()
normal.finish()
check(storedSession() == nil, "normal termination clears own marker")
check(logs.contains(where: { $0.contains("termination_completed reason=quit_requested_user_or_system") }), "normal exit source is not falsely inferred")
let completedLogCount = logs.count
normal.finish()
normal.markRunning()
check(logs.count == completedLogCount && storedSession() == nil, "finished session is idempotent and cannot restart")

for reason in [AppRunDiagnostics.TerminationReason.duplicateInstance, .startupFailure] {
    reset()
    let owner = make("running-owner")
    owner.markRunning()
    let rejected = make("rejected", pid: 456)
    rejected.recordLaunchAttempt()
    rejected.recordTerminationRequest(reason)
    rejected.recordTerminationRequest()
    rejected.markRunning()
    rejected.finish()
    check(storedSession() == "running-owner", "\(reason.rawValue) preserves existing process marker")
    check(logs.last?.contains("termination_completed reason=\(reason.rawValue)") == true, "\(reason.rawValue) retains specific exit reason")
    owner.finish()
    check(storedSession() == nil, "owner can still finish after \(reason.rawValue)")
}

reset()
defaults.set(["session": "previous", "pid": 789, "version": "0.0.3"], forKey: AppRunDiagnostics.activeRunKey)
let failed = make("failed-before-running")
failed.recordTerminationRequest(.startupFailure)
failed.finish()
check(storedSession() == "previous", "startup failure preserves previous incomplete-run evidence")
let recovered = make("recovered")
recovered.markRunning()
check(storedSession() == "recovered", "accepted run replaces previous incomplete marker")
check(logs.filter { $0.contains("previous_run_missing_normal_exit") }.count == 1, "accepted run records incomplete previous exit exactly once")
check(logs.contains { $0.contains("previous_pid=789 previous_version=0.0.3") }, "incomplete exit includes previous pid/version")
check(logs.contains { $0.contains("force quit or power loss") } && !logs.contains { $0.lowercased().contains("crash") }, "incomplete exit does not assert a crash")
recovered.markRunning()
check(logs.filter { $0.contains("previous_run_missing_normal_exit") }.count == 1, "repeated markRunning does not warn about itself")
recovered.finish()

reset()
let oldOwner = make("old-owner")
oldOwner.markRunning()
let newOwner = make("new-owner")
newOwner.markRunning()
oldOwner.finish()
check(storedSession() == "new-owner", "old process cannot clear another session's marker")
check(logs.contains { $0.contains("run_marker_preserved reason=owned_by_another_session") }, "ownership mismatch is diagnosed")
newOwner.finish()
check(storedSession() == nil, "current owner clears its own marker")

reset()
let notStarted = make("never-started")
defaults.set(["session": "somebody-else"], forKey: AppRunDiagnostics.activeRunKey)
notStarted.finish()
check(storedSession() == "somebody-else", "unstarted process cannot clear another process marker")
print("PASSED \(passed) lifecycle diagnostics assertions")
