using PiaoPal.Core;
using System.Text.Json;

var checks = 0;
void Check(bool condition, string label)
{
    checks++;
    if (!condition) throw new InvalidOperationException("FAIL: " + label);
}
void Near(double actual, double expected, double tolerance, string label)
    => Check(Math.Abs(actual - expected) <= tolerance, $"{label}: {actual} vs {expected}");
PetMotion Motion(string skin = "piaopiao", double dpi = 1)
{
    var motion = new PetMotion { SkinId = skin, PixelsPerDip = dpi };
    motion.SetScreens([new(0, 0, 1600 * dpi, 1000 * dpi)]);
    motion.Relocate(new(200 * dpi, 300 * dpi));
    return motion;
}
double Advance(PetMotion motion, DesktopPoint target, double seconds, int fps = 60)
{
    double distance = 0;
    for (var i = 0; i < (int)Math.Round(seconds * fps); i++) distance += motion.Tick(1.0 / fps, target).DistancePoints;
    return distance;
}
bool IsInside(PetMotion motion, DesktopRect screen)
{
    var marginX = Math.Min(32 * motion.Scale * motion.PixelsPerDip, screen.Width / 2);
    var marginY = Math.Min(32 * motion.Scale * motion.PixelsPerDip, screen.Height / 2);
    return motion.Position.X >= screen.X + marginX && motion.Position.X <= screen.Right - marginX
        && motion.Position.Y >= screen.Y + marginY && motion.Position.Y <= screen.Bottom - marginY;
}

foreach (var skin in AppSettings.SkinIds)
{
    var motion = Motion(skin);
    var initial = motion.Position;
    var distance = Advance(motion, new(1200, 280), 2);
    Check(motion.Position.X > initial.X + 200, skin + " follows the pointer");
    Near(distance, DesktopPoint.Distance(initial, motion.Position), .001, skin + " counts actual displacement");
    Check(motion.Animation == PetAnimation.E, skin + " faces east");
    Check(motion.Scale == 1, skin + " defaults to 1x");
    var stoppedAt = Advance(motion, new(1200, 280), 15);
    Check(stoppedAt >= 0 && motion.Animation is PetAnimation.Idle or PetAnimation.ScratchSelf,
        skin + " stops near a reachable target");
    var quietPosition = motion.Position;
    Near(Advance(motion, new(1200, 280), 2), 0, .00001, skin + " idle does not add distance");
    Check(motion.Position == quietPosition, skin + " idle does not drift");

    var healthy = Motion(skin);
    var invalid = Motion(skin);
    Advance(healthy, new(1400, 280), .5);
    Advance(invalid, new(1400, 280), .5);
    foreach (var point in new[] { new DesktopPoint(double.NaN, 200), new DesktopPoint(200, double.PositiveInfinity), new DesktopPoint(1e300, -1e300) })
    {
        var bad = invalid.Tick(1.0 / 60, point);
        Check(bad.DistancePoints == 0 && bad.Position.IsValid, skin + " ignores bad cursor");
    }
    foreach (var dt in new[] { double.NaN, double.PositiveInfinity, 0, -1 })
        Check(invalid.Tick(dt, new(1400, 280)).DistancePoints == 0, skin + " ignores bad dt");
    Advance(healthy, new(1400, 280), 2);
    Advance(invalid, new(1400, 280), 2);
    Near(invalid.Position.X, healthy.Position.X, .000001, skin + " recovers without poisoned velocity");
    Near(invalid.Position.Y, healthy.Position.Y, .000001, skin + " recovers Y");

    invalid.SetResting(true);
    var naps = 0;
    for (var i = 0; i < 180; i++) if (invalid.Tick(1.0 / 60, new(1400, 700)).StartedNap) naps++;
    Check(naps == 1 && invalid.Animation == PetAnimation.Sleeping, skin + " forced rest records one nap");
    invalid.SetScreens([new(-600, -300, 400, 250)]);
    var recovered = invalid.Position;
    var dormantDistance = Advance(invalid, new(1400, 700), 120);
    Check(invalid.IsResting && invalid.Animation == PetAnimation.Sleeping, skin + " shrink retains forced rest");
    Check(IsInside(invalid, new(-600, -300, 400, 250)), skin + " sleeping pet recovers onto negative-coordinate monitor");
    Near(dormantDistance, 0, 0, skin + " recovery and sleep create no distance");
    Check(invalid.Position == recovered, skin + " remains stable after recovery");
    invalid.SetResting(false);
    Advance(invalid, new(-550, -250), 2);
    Check(!invalid.IsResting && invalid.Position.IsValid, skin + " wakes after display change");
}

foreach (var fps in new[] { 30, 60, 120 })
{
    var motion = Motion();
    var distance = Advance(motion, new(1400, 280), 2, fps);
    var reference = Motion();
    var referenceDistance = Advance(reference, new(1400, 280), 2, 120);
    Near(distance, referenceDistance, 1.5, $"movement is frame-rate independent at {fps} FPS");
}
var standardDpi = Motion(dpi: 1);
var highDpi = Motion(dpi: 2);
var standardDistance = Advance(standardDpi, new(1400, 280), 2);
var highDistance = Advance(highDpi, new(2800, 560), 2);
Near(standardDistance, highDistance, .00001, "DPI scaling preserves logical distance and speed");
Near(standardDpi.Position.X * 2, highDpi.Position.X, .00001, "DPI scales physical position");

var screens = new[] { new DesktopRect(-1500, -700, 1200, 700), new DesktopRect(200, 100, 1200, 900) };
var multi = new PetMotion();
multi.SetScreens(screens);
multi.Relocate(new(-800, -400));
var jump = multi.Tick(.001, new(1000, 500));
Check(IsInside(multi, screens[1]), "disconnected monitor transition remains on a real display");
Near(jump.DistancePoints, 0, 0, "cross-monitor re-anchor adds no walking distance");
Advance(multi, new(1000, 500), 4);
Check(IsInside(multi, screens[1]), "following stays within real work area");
var stable = multi.Position;
multi.SetScreens([]);
Check(multi.Tick(2, new(-800, -400)).Position == stable, "no-display interval pauses position");
multi.SetScreens([new(double.NaN, 0, 100, 100), new(-10, -10, -2, 4)]);
Check(multi.Tick(2, new(0, 0)).Position == stable, "invalid displays pause safely");
multi.SetScreens([new(-15, -15, 12, 8)]);
Check(IsInside(multi, new(-15, -15, 12, 8)), "tiny screens clamp to safe center");
Check(multi.Position.IsValid, "tiny screen remains finite");
var tinyPos = multi.Position;
multi.Relocate(new(double.PositiveInfinity, double.NaN));
Check(multi.Position == tinyPos, "invalid relocation ignored");

var sleeping = Motion();
var asleep = false;
var scratched = false;
for (var i = 0; i < 2500; i++)
{
    var frame = sleeping.Tick(1.0 / 60, new(200, 280));
    asleep |= frame.Animation == PetAnimation.Sleeping;
    scratched |= frame.StartedScratch;
    Near(frame.DistancePoints, 0, 0, "quiet natural behavior never walks");
}
Check(asleep && scratched, "natural idle produces grooming and sleep");
sleeping.SetScreens([new(0, 0, 100, 100)]);
Check(IsInside(sleeping, new(0, 0, 100, 100)), "naturally sleeping pet is recovered after shrink");

foreach (var skin in AppSettings.SkinIds)
foreach (var animation in Enum.GetValues<PetAnimation>())
foreach (var time in new[] { 0, .1, 40, double.MaxValue, double.NaN, double.PositiveInfinity })
{
    var pose = SpriteAnimation.GetPose(animation, time, time, skin);
    Check(pose.Columns > 0 && pose.Rows > 0 && pose.Column >= 0 && pose.Column < pose.Columns
        && pose.Row >= 0 && pose.Row < pose.Rows && double.IsFinite(pose.BreathScale), "atlas pose remains valid");
}
var expectedDirections = new[] { PetAnimation.N, PetAnimation.NE, PetAnimation.E, PetAnimation.SE,
    PetAnimation.S, PetAnimation.SW, PetAnimation.W, PetAnimation.NW };
for (var row = 0; row < 8; row++)
{
    var pose = SpriteAnimation.GetPose(expectedDirections[row], 0, .6, "piaopiao");
    Check(pose.UsesWalkingAtlas && pose.Row == row && pose.Column == 2 && pose.Columns == 4 && pose.Rows == 8,
        "PiaoPiao uses authored 4x8 walk mapping");
    var fallback = SpriteAnimation.GetPose(expectedDirections[row], 0, .6, "piaopiao", false);
    Check(!fallback.UsesWalkingAtlas && fallback.Columns == 8 && fallback.Rows == 4, "walk atlas fallback is safe");
}

var temp = Path.Combine(Path.GetTempPath(), "piaopal-core-tests-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(temp);
var fixedDay = new DateTimeOffset(2026, 11, 6, 12, 0, 0, TimeSpan.FromHours(8));
try
{
    var storage = Path.Combine(temp, "normal");
    using (var store = new SettingsStore(storage, fixedDay))
    {
        Check(store.Settings.Scale == 1 && store.Settings.SkinId == "piaopiao", "fresh defaults are 1x PiaoPiao");
        Check(store.Stats.SessionCount == 1 && store.Stats.Streak == 1, "first session initialized");
        store.Settings.Scale = 1.75;
        store.Settings.Speed = 2.5;
        store.Settings.SkinId = "dog";
        store.Settings.Nickname = "小伙伴";
        store.Settings.Language = "en";
        store.AddDistance(125.25);
        store.RecordNap(); store.RecordScratch();
        store.Save(); store.Save();
        store.AddDistance(25.5); // Final partial interval must be flushed by Dispose.
    }
    using (var store = new SettingsStore(storage, fixedDay.AddHours(1)))
    {
        Near(store.Stats.DistancePoints, 150.75, .00001, "partial interval survives a new instance");
        Check(store.Stats.SessionCount == 2 && store.Stats.Streak == 1, "same-day restart keeps streak");
        Check(store.Settings.Scale == 1.75 && store.Settings.Speed == 2.5 && store.Settings.SkinId == "dog"
            && store.Settings.Nickname == "小伙伴" && store.Settings.Language == "en", "saved custom preferences survive restart");
        Check(store.Stats.Naps == 1 && store.Stats.Scratches == 1, "activity counters survive restart");
        store.AddDistance(double.NaN); store.AddDistance(double.PositiveInfinity); store.AddDistance(-2);
        Near(store.Stats.DistancePoints, 150.75, .00001, "invalid distance ignored");
        Parallel.For(0, 1000, _ => store.AddDistance(.5));
        Near(store.Stats.DistancePoints, 650.75, .00001, "concurrent distance is not lost");
    }
    using (var store = new SettingsStore(storage, fixedDay.AddDays(1)))
        Check(store.Stats.Streak == 2, "next day increments streak once");
    using (var store = new SettingsStore(storage, fixedDay.AddDays(4)))
        Check(store.Stats.Streak == 1, "missed days restart streak");
    using (var store = new SettingsStore(storage, fixedDay.AddDays(3)))
        Check(store.Stats.Streak == 1 && store.Stats.LastLaunchDay == DateOnly.FromDateTime(fixedDay.AddDays(4).DateTime),
            "clock moving backward preserves last known launch day");
    Check(!Directory.EnumerateFiles(storage, "*.tmp").Any(), "successful saves leave no temporary files");

    var corrupted = Path.Combine(temp, "corrupt");
    using (var store = new SettingsStore(corrupted, fixedDay))
    { store.Settings.Nickname = "backup-survives"; store.AddDistance(123); store.Save(); }
    var original = "{broken json preserved";
    File.WriteAllText(Path.Combine(corrupted, "state.json"), original);
    using (var recovered = new SettingsStore(corrupted, fixedDay))
    {
        Check(recovered.RecoveryMessage is not null, "broken JSON reports recovery");
        Check(recovered.Settings.Nickname == "backup-survives", "valid backup restored");
        Near(recovered.Stats.DistancePoints, 123, 0, "backup retains saved statistics");
    }
    var quarantined = Directory.GetFiles(corrupted, "state.corrupt.*.json");
    Check(quarantined.Length == 1 && File.ReadAllText(quarantined[0]) == original, "corrupt input is preserved byte-for-byte");

    var freshCorrupt = Path.Combine(temp, "fresh-corrupt"); Directory.CreateDirectory(freshCorrupt);
    File.WriteAllText(Path.Combine(freshCorrupt, "state.json"), "{}");
    using (var recovered = new SettingsStore(freshCorrupt, fixedDay))
        Check(recovered.Settings.Scale == 1 && recovered.RecoveryMessage is not null, "incomplete document falls back to safe defaults");
    Check(Directory.GetFiles(freshCorrupt, "state.corrupt.*.json").Length == 1, "incomplete document also preserved");

    foreach (var malformed in new[] { "null", "[]", "{\"schemaVersion\":null}", "{\"schemaVersion\":\"wrong\"}", "{\"schemaVersion\":1.5}" })
    {
        var directory = Path.Combine(temp, "malformed-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        File.WriteAllText(Path.Combine(directory, "state.json"), malformed);
        using var recovered = new SettingsStore(directory, fixedDay);
        Check(recovered.RecoveryMessage is not null && recovered.Settings.Scale == 1,
            "malformed document shape recovers instead of crashing at startup");
        Check(File.ReadAllText(Directory.GetFiles(directory, "state.corrupt.*.json").Single()) == malformed,
            "malformed schema input is preserved");
    }
    var bothCorrupt = Path.Combine(temp, "both-corrupt"); Directory.CreateDirectory(bothCorrupt);
    File.WriteAllText(Path.Combine(bothCorrupt, "state.json"), "bad-main");
    File.WriteAllText(Path.Combine(bothCorrupt, "state.json.bak"), "bad-backup");
    using (var recovered = new SettingsStore(bothCorrupt, fixedDay))
        Check(recovered.RecoveryMessage is not null && recovered.Settings.Scale == 1,
            "two corrupt copies recover to safe defaults");
    var preservedContents = Directory.GetFiles(bothCorrupt, "*corrupt*.json").Select(File.ReadAllText).ToHashSet();
    Check(preservedContents.SetEquals(new[] { "bad-main", "bad-backup" }),
        "both damaged files remain recoverable after saving fresh state");

    var missingMain = Path.Combine(temp, "missing-main");
    using (var store = new SettingsStore(missingMain, fixedDay))
    { store.Settings.Nickname = "from-backup"; store.AddDistance(45); store.Save(); }
    File.Delete(Path.Combine(missingMain, "state.json"));
    using (var recovered = new SettingsStore(missingMain, fixedDay))
        Check(recovered.Settings.Nickname == "from-backup" && recovered.Stats.DistancePoints == 45
            && recovered.RecoveryMessage is not null, "missing main file restores valid backup");

    var future = Path.Combine(temp, "future"); Directory.CreateDirectory(future);
    var futureText = "{\"schemaVersion\":999,\"settings\":{},\"stats\":{}}";
    File.WriteAllText(Path.Combine(future, "state.json"), futureText);
    var rejectedFuture = false;
    try { using var store = new SettingsStore(future, fixedDay); }
    catch (InvalidDataException) { rejectedFuture = true; }
    Check(rejectedFuture && File.ReadAllText(Path.Combine(future, "state.json")) == futureText,
        "future schema is rejected without overwriting or quarantining its data");
    Check(Directory.GetFiles(future).Length == 1, "unsupported schema writes no replacement");

    var normalize = Path.Combine(temp, "normalize");
    using (var store = new SettingsStore(normalize, fixedDay))
    {
        store.Settings.Scale = double.NaN; store.Settings.Speed = double.PositiveInfinity;
        store.Settings.SkinId = "missing"; store.Settings.Nickname = new string('x', 70);
        store.Settings.Language = "unknown";
        store.Save();
        Check(store.Settings.Scale == 1 && store.Settings.Speed == 1 && store.Settings.SkinId == "piaopiao"
            && store.Settings.Nickname.Length == 40 && store.Settings.Language == "zh-CN", "unsafe preferences normalize before persistence");
        store.AddDistance(2.5 / .00027);
        Check(store.Stats.Level == 2, "level matches macOS distance threshold");
        Near(store.Stats.XpProgress, 0, .000001, "level threshold resets XP progress");
    }
    var disposed = new SettingsStore(Path.Combine(temp, "dispose"), fixedDay);
    disposed.AddDistance(42); disposed.Dispose(); disposed.Dispose();
    using (var reread = new SettingsStore(Path.Combine(temp, "dispose"), fixedDay))
        Near(reread.Stats.DistancePoints, 42, 0, "Dispose is idempotent");
}
finally { Directory.Delete(temp, recursive: true); }
Console.WriteLine($"PASS: {checks} core checks — six pets, invalid-input recovery, real monitor bounds, DPI, animation frames, atomic settings, backup recovery, session stats and exit flush");
