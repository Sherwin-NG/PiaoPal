import Foundation
import Combine
import os.lock

/// Persistent lifetime stats for the cat.
/// Thread-safe: addDistance/recordNap/recordScratch may be called from any thread.
final class CatStats: ObservableObject {
    /// Distance is flushed on this cadence and on sleep/resign. One minute keeps
    /// the write cheap while bounding how much a crash or power loss can drop.
    static let snapshotInterval: TimeInterval = 60

    private enum Key {
        static let distance      = "cat_stat_distance_pts"
        static let naps          = "cat_stat_naps"
        static let scratches     = "cat_stat_scratches"
        static let firstLaunch   = "cat_stat_first_launch"
        static let streak        = "cat_streak"
        static let streakDate    = "cat_streak_last_date"
        static let dockedCount   = "cat_stat_docked_count"
        static let laserSessions = "cat_stat_laser_sessions"
        static let skinsUsed     = "cat_stat_skins_used"
    }

    private struct Snapshot: Codable {
        var version: Int
        var distancePoints: Double
        var naps: Int
        var scratches: Int
        var streak: Int
        var streakDate: Double
        var dockedCount: Int
        var laserSessions: Int
        var usedSkinIDs: [String]
        var firstLaunch: Double
    }

    @Published private(set) var distancePoints: Double
    @Published private(set) var naps: Int
    @Published private(set) var scratches: Int
    @Published private(set) var streak: Int = 1
    @Published private(set) var dockedCount: Int = 0
    @Published private(set) var laserSessions: Int = 0
    @Published private(set) var usedSkinIDs: Set<String> = []
    let firstLaunchDate: Date

    private var pendingDistance: Double = 0
    private var _lock = os_unfair_lock()
    private let defaults: UserDefaults
    private let snapshotURL: URL?
    private var flushTimer: Timer?

    /// `snapshotURL` is an atomic sidecar. Existing UserDefaults keys stay the
    /// source that older builds read; the sidecar survives a force-kill that
    /// lands before `cfprefsd` flushes.
    init(defaults: UserDefaults = .standard, snapshotURL: URL? = nil) {
        self.defaults = defaults
        self.snapshotURL = snapshotURL
        let snapshot = Self.readSnapshot(at: snapshotURL)

        var distance = defaults.double(forKey: Key.distance)
        var napCount = defaults.integer(forKey: Key.naps)
        var scratchCount = defaults.integer(forKey: Key.scratches)
        var docks = defaults.integer(forKey: Key.dockedCount)
        var lasers = defaults.integer(forKey: Key.laserSessions)
        var skins = Set(defaults.stringArray(forKey: Key.skinsUsed) ?? [])
        var streakValue = defaults.integer(forKey: Key.streak)
        var streakDate = defaults.object(forKey: Key.streakDate) as? Double
        var firstTimestamp = defaults.object(forKey: Key.firstLaunch) as? Double

        if let snapshot {
            if snapshot.distancePoints.isFinite {
                distance = max(distance, min(Self.maximumDistance, max(0, snapshot.distancePoints)))
            }
            napCount = max(napCount, max(0, snapshot.naps))
            scratchCount = max(scratchCount, max(0, snapshot.scratches))
            docks = max(docks, max(0, snapshot.dockedCount))
            lasers = max(lasers, max(0, snapshot.laserSessions))
            skins.formUnion(snapshot.usedSkinIDs.filter { !$0.isEmpty })
            if snapshot.streakDate.isFinite, snapshot.streakDate > 0,
               streakDate == nil || snapshot.streakDate > streakDate! {
                streakDate = snapshot.streakDate
                if snapshot.streak >= 1 { streakValue = snapshot.streak }
            }
            if snapshot.firstLaunch.isFinite, snapshot.firstLaunch > 0 {
                if let existing = firstTimestamp, existing > 0 {
                    firstTimestamp = min(existing, snapshot.firstLaunch)
                } else {
                    firstTimestamp = snapshot.firstLaunch
                }
            }
        }
        if !distance.isFinite || distance < 0 { distance = 0 }
        distance = min(Self.maximumDistance, distance)

        distancePoints = distance
        naps = napCount
        scratches = scratchCount
        dockedCount = docks
        laserSessions = lasers
        usedSkinIDs = skins
        if let firstTimestamp, firstTimestamp.isFinite, firstTimestamp > 0 {
            firstLaunchDate = Date(timeIntervalSince1970: firstTimestamp)
        } else {
            let now = Date()
            firstLaunchDate = now
            defaults.set(now.timeIntervalSince1970, forKey: Key.firstLaunch)
        }
        updateStreak(saved: streakValue, savedDate: streakDate)
        defaults.set(distancePoints, forKey: Key.distance)
        defaults.set(naps, forKey: Key.naps)
        defaults.set(scratches, forKey: Key.scratches)
        defaults.set(dockedCount, forKey: Key.dockedCount)
        defaults.set(laserSessions, forKey: Key.laserSessions)
        defaults.set(Array(usedSkinIDs), forKey: Key.skinsUsed)
        defaults.synchronize()
        writeSnapshot()

        guard Thread.isMainThread else { return }
        let timer = Timer(timeInterval: Self.snapshotInterval, repeats: true) { [weak self] _ in
            self?.savePendingDistance()
        }
        RunLoop.main.add(timer, forMode: .common)
        flushTimer = timer
    }

    deinit {
        if Thread.isMainThread { flushTimer?.invalidate() }
    }

    static func applicationSupportSnapshotURL() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return base.appendingPathComponent("PiaoPal/cat-stats.json")
    }

    // MARK: – Write (render thread safe)

    func addDistance(_ pts: Float) {
        guard pts.isFinite, pts > 0 else { return }
        os_unfair_lock_lock(&_lock)
        pendingDistance += Double(pts)
        os_unfair_lock_unlock(&_lock)
    }

    func recordNap() { recordCounter { self.naps += 1; self.defaults.set(self.naps, forKey: Key.naps) } }
    func recordScratch() { recordCounter { self.scratches += 1; self.defaults.set(self.scratches, forKey: Key.scratches) } }
    func recordDocked() { recordCounter { self.dockedCount += 1; self.defaults.set(self.dockedCount, forKey: Key.dockedCount) } }
    func recordLaserSession() { recordCounter { self.laserSessions += 1; self.defaults.set(self.laserSessions, forKey: Key.laserSessions) } }

    func recordSkinUsed(_ id: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.usedSkinIDs.contains(id) else { return }
            self.usedSkinIDs.insert(id)
            self.defaults.set(Array(self.usedSkinIDs), forKey: Key.skinsUsed)
            self.savePendingDistance()
        }
    }

    func reset() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.reset() }
            return
        }
        os_unfair_lock_lock(&_lock)
        pendingDistance = 0
        os_unfair_lock_unlock(&_lock)
        distancePoints = 0
        naps = 0
        scratches = 0
        dockedCount = 0
        laserSessions = 0
        usedSkinIDs = []
        defaults.removeObject(forKey: Key.distance)
        defaults.removeObject(forKey: Key.naps)
        defaults.removeObject(forKey: Key.scratches)
        defaults.removeObject(forKey: Key.dockedCount)
        defaults.removeObject(forKey: Key.laserSessions)
        defaults.removeObject(forKey: Key.skinsUsed)
        defaults.synchronize()
        // Drop the sidecar first. A failed rewrite must not restore cleared progress.
        if let snapshotURL {
            try? FileManager.default.removeItem(at: snapshotURL)
        }
        writeSnapshot()
    }

    // MARK: – Streak

    private func updateStreak(saved: Int, savedDate: Double?) {
        let cal   = Calendar.current
        let today = cal.startOfDay(for: Date())

        if let savedDate, savedDate.isFinite {
            let last = cal.startOfDay(for: Date(timeIntervalSince1970: savedDate))
            let diff = cal.dateComponents([.day], from: last, to: today).day ?? 0
            switch diff {
            case 0:  streak = max(1, saved)
            case 1:  streak = saved + 1
            default: streak = 1
            }
        } else {
            streak = 1
        }

        defaults.set(today.timeIntervalSince1970, forKey: Key.streakDate)
        defaults.set(streak, forKey: Key.streak)
    }

    // MARK: – Level / XP

    private static let maximumDistance: Double = 1e15

    /// 1 logical point ≈ 0.27 mm at ~94 logical PPI.
    var distanceMeters: Double {
        guard distancePoints.isFinite, distancePoints > 0 else { return 0 }
        return min(Self.maximumDistance, distancePoints) * 0.000_27
    }

    /// Level = floor(sqrt(meters / 2.5)) + 1  (level 2 at ~2.5 m, level 10 at ~202 m)
    var level: Int {
        let meters = distanceMeters
        guard meters.isFinite, meters >= 0 else { return 1 }
        let value = (meters / 2.5).squareRoot()
        guard value.isFinite, value >= 0, value < Double(Int.max) else { return 1 }
        return Int(value) + 1
    }

    /// Progress within current level [0, 1).
    var xpProgress: Double {
        let meters = distanceMeters
        let n    = Double(level - 1)
        let prev = n * n * 2.5
        let next = (n + 1) * (n + 1) * 2.5
        guard meters.isFinite, prev.isFinite, next.isFinite, next > prev else { return 1 }
        return min(1, max(0, (meters - prev) / (next - prev)))
    }

    /// Meters remaining until the next level-up.
    var metersToNextLevel: Double {
        let meters = distanceMeters
        guard meters.isFinite else { return 0 }
        let n = Double(level)
        let remaining = n * n * 2.5 - meters
        return remaining.isFinite ? max(0, remaining) : 0
    }

    /// Short label for the XP bar: "12m / 40m"
    var xpLabel: String {
        let meters = distanceMeters
        let n    = Double(level - 1)
        let next = (n + 1) * (n + 1) * 2.5
        guard meters.isFinite, meters >= 0, meters < Double(Int.max),
              next.isFinite, next >= 0, next < Double(Int.max) else { return "0m / 0m" }
        return "\(Int(meters))m / \(Int(next))m"
    }

    var daysTogether: Int {
        Calendar.current.dateComponents([.day], from: firstLaunchDate, to: .now).day ?? 0
    }

    // MARK: – Persistence

    /// Flushes the partial distance interval and rewrites the atomic snapshot.
    /// Safe to call from any thread; the write itself always hops to main.
    func savePendingDistance() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.savePendingDistance() }
            return
        }
        os_unfair_lock_lock(&_lock)
        let d = pendingDistance
        pendingDistance = 0
        os_unfair_lock_unlock(&_lock)
        if d.isFinite, d > 0 {
            let sum = distancePoints + d
            if sum.isFinite, sum > 0 {
                distancePoints = min(Self.maximumDistance, sum)
                defaults.set(distancePoints, forKey: Key.distance)
            }
        }
        defaults.synchronize()
        writeSnapshot()
    }

    private func recordCounter(_ mutate: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            mutate()
            self.savePendingDistance()
        }
    }

    private static func readSnapshot(at url: URL?) -> Snapshot? {
        guard let url, let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              snapshot.version == 1 else { return nil }
        return snapshot
    }

    private func writeSnapshot() {
        guard let snapshotURL else { return }
        let snapshot = Snapshot(
            version: 1,
            distancePoints: distancePoints,
            naps: naps,
            scratches: scratches,
            streak: streak,
            streakDate: defaults.object(forKey: Key.streakDate) as? Double ?? 0,
            dockedCount: dockedCount,
            laserSessions: laserSessions,
            usedSkinIDs: usedSkinIDs.sorted(),
            firstLaunch: firstLaunchDate.timeIntervalSince1970
        )
        let directory = snapshotURL.deletingLastPathComponent()
        let temp = directory.appendingPathComponent(".\(snapshotURL.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: temp)
            let handle = try FileHandle(forWritingTo: temp)
            try handle.synchronize()
            try handle.close()
            if FileManager.default.fileExists(atPath: snapshotURL.path) {
                _ = try FileManager.default.replaceItemAt(snapshotURL, withItemAt: temp)
            } else {
                try FileManager.default.moveItem(at: temp, to: snapshotURL)
            }
        } catch {
            try? FileManager.default.removeItem(at: temp)
        }
    }
}
