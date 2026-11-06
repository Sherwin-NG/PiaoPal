using System.Text.Json;
using System.Text.Json.Serialization;

namespace PiaoPal.Core;

/// <summary>
/// Stores one versioned document per profile. The shell provides a private user directory
/// and owns the per-profile process lock. Call Save periodically and Dispose on normal quit.
/// </summary>
public sealed class SettingsStore : IDisposable
{
    private sealed class StateDocument
    {
        public int SchemaVersion { get; set; } = 1;
        public AppSettings Settings { get; set; } = new();
        public PetStats Stats { get; set; } = new();
    }
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
        WriteIndented = true,
        NumberHandling = JsonNumberHandling.AllowNamedFloatingPointLiterals,
    };
    private readonly object gate = new();
    private readonly DateTimeOffset launchTime;
    private bool disposed;
    public string DirectoryPath { get; }
    public string StatePath { get; }
    public string BackupPath => StatePath + ".bak";
    public string? RecoveryMessage { get; private set; }
    public AppSettings Settings { get; }
    public PetStats Stats { get; }

    public SettingsStore(string directory, DateTimeOffset? now = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(directory);
        DirectoryPath = Path.GetFullPath(directory);
        StatePath = Path.Combine(DirectoryPath, "state.json");
        launchTime = now ?? DateTimeOffset.Now;
        Directory.CreateDirectory(DirectoryPath);
        var document = LoadDocument();
        Settings = document.Settings;
        Stats = document.Stats;
        Settings.Normalize();
        Stats.Normalize(launchTime);
        var today = DateOnly.FromDateTime(launchTime.DateTime);
        var days = today.DayNumber - Stats.LastLaunchDay.DayNumber;
        if (Stats.LastLaunchDay == default || days > 1) Stats.Streak = 1;
        else if (days == 1) Stats.Streak = Increment(Stats.Streak);
        // A backwards system clock does not destroy a valid existing streak.
        if (today >= Stats.LastLaunchDay) Stats.LastLaunchDay = today;
        Stats.SessionCount = Increment(Stats.SessionCount);
        Save();
    }

    private StateDocument LoadDocument()
    {
        if (!File.Exists(StatePath))
        {
            if (File.Exists(BackupPath))
            {
                try
                {
                    var recovered = ReadDocument(BackupPath);
                    RecoveryMessage = "Recovered settings from the backup because the main file was missing.";
                    return recovered;
                }
                catch (JsonException) { PreserveInvalidBackup(); }
            }
            return new();
        }
        try { return ReadDocument(StatePath); }
        catch (JsonException)
        {
            // Preserve broken input before starting a fresh document. Unknown future schemas
            // intentionally throw InvalidDataException instead and are never overwritten.
            var quarantine = Path.Combine(DirectoryPath,
                $"state.corrupt.{DateTimeOffset.UtcNow:yyyyMMdd-HHmmss}.{Guid.NewGuid():N}.json");
            File.Move(StatePath, quarantine);
            RecoveryMessage = "The unreadable settings file was preserved as " + Path.GetFileName(quarantine) + ".";
            if (File.Exists(BackupPath))
            {
                try
                {
                    var recovered = ReadDocument(BackupPath);
                    RecoveryMessage += " The last valid backup was restored.";
                    return recovered;
                }
                catch (JsonException) { PreserveInvalidBackup(); }
            }
            return new();
        }
    }

    private void PreserveInvalidBackup()
    {
        var quarantine = Path.Combine(DirectoryPath,
            $"state.backup.corrupt.{DateTimeOffset.UtcNow:yyyyMMdd-HHmmss}.{Guid.NewGuid():N}.json");
        File.Move(BackupPath, quarantine);
        RecoveryMessage = (RecoveryMessage is null ? "" : RecoveryMessage + " ")
            + "An unreadable backup was preserved as " + Path.GetFileName(quarantine) + ".";
    }

    private static StateDocument ReadDocument(string path)
    {
        using var stream = File.OpenRead(path);
        using var json = JsonDocument.Parse(stream);
        var root = json.RootElement;
        if (root.ValueKind != JsonValueKind.Object
            || !root.TryGetProperty("schemaVersion", out var schema)
            || schema.ValueKind != JsonValueKind.Number
            || !schema.TryGetInt32(out var version))
            throw new JsonException("Settings document has no valid schema version.");
        if (version != 1)
            throw new InvalidDataException($"Unsupported PiaoPal settings schema {version}; the existing file was not changed.");
        if (!root.TryGetProperty("settings", out _) || !root.TryGetProperty("stats", out _))
            throw new JsonException("Settings document is incomplete.");
        var document = root.Deserialize<StateDocument>(JsonOptions)
            ?? throw new JsonException("Settings document is null.");
        if (document.Settings is null || document.Stats is null)
            throw new JsonException("Settings document is missing settings or statistics.");
        return document;
    }

    public void AddDistance(double points)
    {
        if (!double.IsFinite(points) || points <= 0) return;
        lock (gate)
        {
            ObjectDisposedException.ThrowIf(disposed, this);
            Stats.DistancePoints = Math.Min(1e15, Stats.DistancePoints + Math.Min(points, 1e15));
        }
    }

    public void RecordNap()
    {
        lock (gate) { ObjectDisposedException.ThrowIf(disposed, this); Stats.Naps = Increment(Stats.Naps); }
    }
    public void RecordScratch()
    {
        lock (gate) { ObjectDisposedException.ThrowIf(disposed, this); Stats.Scratches = Increment(Stats.Scratches); }
    }

    public void Save()
    {
        lock (gate)
        {
            ObjectDisposedException.ThrowIf(disposed, this);
            SaveCore();
        }
    }

    private void SaveCore()
    {
        Settings.Normalize();
        Stats.Normalize(launchTime);
        var temporary = Path.Combine(DirectoryPath, $"state.{Guid.NewGuid():N}.tmp");
        try
        {
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write,
                       FileShare.None, 4096, FileOptions.WriteThrough))
            {
                JsonSerializer.Serialize(stream, new StateDocument { Settings = Settings, Stats = Stats }, JsonOptions);
                stream.Flush(flushToDisk: true);
            }
            if (File.Exists(StatePath)) File.Replace(temporary, StatePath, BackupPath);
            else File.Move(temporary, StatePath);
        }
        finally
        {
            if (File.Exists(temporary)) File.Delete(temporary);
        }
    }

    public void Dispose()
    {
        lock (gate)
        {
            if (disposed) return;
            SaveCore();
            disposed = true;
        }
    }

    private static int Increment(int value) => value < int.MaxValue ? value + 1 : int.MaxValue;
}
