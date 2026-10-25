import Foundation

let distanceKey = "cat_stat_distance_pts"

func near(_ actual: Double, _ expected: Double, _ message: String) {
    precondition(abs(actual - expected) < 0.0001, "\(message): \(actual), expected \(expected)")
}

// Separate processes verify that a short session survives a real process exit,
// rather than merely reading the same UserDefaults object's cached values.
if CommandLine.arguments.count == 3 {
    let defaults = UserDefaults(suiteName: CommandLine.arguments[2])!
    let stats = CatStats(defaults: defaults)
    switch CommandLine.arguments[1] {
    case "--write":
        stats.addDistance(1_600)
        stats.savePendingDistance()
    case "--read":
        near(stats.distancePoints, 1_600, "Short-session distance survives process exit")
    default:
        fatalError("Unknown statistics test mode")
    }
} else {
    let suite = "io.github.sherwinng.PiaoPal.tests.stats.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }

    defaults.set(50.0, forKey: distanceKey)
    let stats = CatStats(defaults: defaults)
    stats.addDistance(125)
    stats.addDistance(75)
    stats.savePendingDistance()
    near(stats.distancePoints, 250, "Pending distance is added to existing lifetime distance")
    near(defaults.double(forKey: distanceKey), 250, "Final distance is persisted immediately")
    stats.savePendingDistance()
    near(stats.distancePoints, 250, "Repeated saves cannot count a step twice")

    DispatchQueue.concurrentPerform(iterations: 8) { _ in
        for _ in 0..<1_000 { stats.addDistance(0.25) }
    }
    stats.savePendingDistance()
    near(stats.distancePoints, 2_250, "Concurrent motion callbacks lose no distance")
    let restored = CatStats(defaults: defaults)
    near(restored.distancePoints, 2_250, "Saved lifetime distance is restored")
    precondition(restored.level == stats.level && restored.xpProgress == stats.xpProgress,
                 "Restored level and XP match the final saved distance")

    let processSuite = suite + ".process"
    let processDefaults = UserDefaults(suiteName: processSuite)!
    defer { processDefaults.removePersistentDomain(forName: processSuite) }
    for mode in ["--write", "--read"] {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        child.arguments = [mode, processSuite]
        try child.run()
        child.waitUntilExit()
        precondition(child.terminationStatus == 0, "Statistics subprocess failed: \(mode)")
    }
    print("PASS: final distance saving, repeated-save idempotence, concurrent accumulation, restored XP and cross-process short-session persistence")
}
