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
    precondition(CatStats.snapshotInterval == 60, "lifetime statistics flush about once a minute")
    let snapshotDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("piaopal-stats-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: snapshotDirectory) }
    let snapshotURL = snapshotDirectory.appendingPathComponent("cat-stats.json")
    func snapshotDefaults(_ name: String) -> UserDefaults {
        let isolated = UserDefaults(suiteName: suite + "." + name)!
        isolated.removePersistentDomain(forName: suite + "." + name)
        return isolated
    }
    let crashDefaults = snapshotDefaults("crash")
    let crashed = CatStats(defaults: crashDefaults, snapshotURL: snapshotURL)
    crashed.addDistance(500)
    crashed.savePendingDistance()
    let revived = CatStats(defaults: snapshotDefaults("revived"), snapshotURL: snapshotURL)
    near(revived.distancePoints, 500, "atomic snapshot survives when UserDefaults were not flushed")
    _ = revived.level
    _ = revived.xpProgress
    _ = revived.xpLabel
    let names = try FileManager.default.contentsOfDirectory(at: snapshotDirectory, includingPropertiesForKeys: nil)
    precondition(names.allSatisfy { !$0.lastPathComponent.contains(".tmp") }, "atomic save leaves no temporary files")

    let mergedURL = snapshotDirectory.appendingPathComponent("merged.json")
    try """
    {"version":1,"distancePoints":80,"naps":2,"scratches":1,"streak":4,"streakDate":0,"dockedCount":3,"laserSessions":1,"usedSkinIDs":["piaopiao"],"firstLaunch":1700000000}
    """.write(to: mergedURL, atomically: true, encoding: .utf8)
    let mergedDefaults = snapshotDefaults("merged")
    mergedDefaults.set(20.0, forKey: distanceKey)
    let merged = CatStats(defaults: mergedDefaults, snapshotURL: mergedURL)
    near(merged.distancePoints, 80, "newer snapshot distance wins over a stale preference")
    precondition(merged.naps == 2 && merged.scratches == 1 && merged.dockedCount == 3 && merged.laserSessions == 1,
                 "snapshot counters merge with preferences")
    precondition(merged.usedSkinIDs.contains("piaopiao"), "snapshot keeps recorded companions")
    let preferredURL = snapshotDirectory.appendingPathComponent("preferred.json")
    try """
    {"version":1,"distancePoints":40,"naps":0,"scratches":0,"streak":1,"streakDate":0,"dockedCount":0,"laserSessions":0,"usedSkinIDs":[],"firstLaunch":1700000000}
    """.write(to: preferredURL, atomically: true, encoding: .utf8)
    let preferredDefaults = snapshotDefaults("preferred")
    preferredDefaults.set(100.0, forKey: distanceKey)
    let preferred = CatStats(defaults: preferredDefaults, snapshotURL: preferredURL)
    near(preferred.distancePoints, 100, "a higher preference value is kept when the snapshot is older")

    let corruptURL = snapshotDirectory.appendingPathComponent("corrupt.json")
    try Data("not-json".utf8).write(to: corruptURL)
    let corruptDefaults = snapshotDefaults("corrupt")
    corruptDefaults.set(40.0, forKey: distanceKey)
    let corrupt = CatStats(defaults: corruptDefaults, snapshotURL: corruptURL)
    near(corrupt.distancePoints, 40, "a corrupt snapshot does not discard saved preferences")
    let futureURL = snapshotDirectory.appendingPathComponent("future.json")
    try """
    {"version":2,"distancePoints":999,"naps":0,"scratches":0,"streak":1,"streakDate":0,"dockedCount":0,"laserSessions":0,"usedSkinIDs":[],"firstLaunch":1700000000}
    """.write(to: futureURL, atomically: true, encoding: .utf8)
    let futureDefaults = snapshotDefaults("future")
    futureDefaults.set(5.0, forKey: distanceKey)
    let future = CatStats(defaults: futureDefaults, snapshotURL: futureURL)
    near(future.distancePoints, 5, "an unknown snapshot version is ignored")

    let hugeURL = snapshotDirectory.appendingPathComponent("huge.json")
    try """
    {"version":1,"distancePoints":1e20,"naps":0,"scratches":0,"streak":1,"streakDate":0,"dockedCount":0,"laserSessions":0,"usedSkinIDs":[],"firstLaunch":1700000000}
    """.write(to: hugeURL, atomically: true, encoding: .utf8)
    let huge = CatStats(defaults: snapshotDefaults("huge"), snapshotURL: hugeURL)
    near(huge.distancePoints, 1e15, "non-finite-scale distance is capped before level math")
    precondition(huge.level >= 1, "level stays representable")
    precondition(huge.xpProgress.isFinite && huge.metersToNextLevel.isFinite, "XP stays finite")
    precondition(!huge.xpLabel.isEmpty, "XP label does not trap")
    let before = huge.distancePoints
    huge.addDistance(.nan)
    huge.addDistance(.infinity)
    huge.addDistance(-5)
    huge.savePendingDistance()
    near(huge.distancePoints, before, "non-finite distance increments are ignored")

    let resetURL = snapshotDirectory.appendingPathComponent("reset.json")
    let resetDefaults = snapshotDefaults("reset")
    let resetStats = CatStats(defaults: resetDefaults, snapshotURL: resetURL)
    resetStats.addDistance(30)
    resetStats.savePendingDistance()
    resetStats.reset()
    let resetAgain = CatStats(defaults: resetDefaults, snapshotURL: resetURL)
    near(resetAgain.distancePoints, 0, "reset clears the atomic snapshot")

    print("PASS: final distance saving, repeated-save idempotence, concurrent accumulation, restored XP, cross-process short-session persistence and crash-safe snapshots")
}
