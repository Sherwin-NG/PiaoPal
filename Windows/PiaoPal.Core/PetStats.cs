using System.Text.Json.Serialization;

namespace PiaoPal.Core;

public sealed class PetStats
{
    public double DistancePoints { get; set; }
    public int SessionCount { get; set; }
    public int Streak { get; set; } = 1;
    public int Naps { get; set; }
    public int Scratches { get; set; }
    public DateTimeOffset FirstLaunch { get; set; }
    public DateOnly LastLaunchDay { get; set; }
    [JsonIgnore] public double DistanceMeters => DistancePoints * .00027;
    [JsonIgnore] public int Level => (int)Math.Min(int.MaxValue - 1d, Math.Floor(Math.Sqrt(DistanceMeters / 2.5))) + 1;
    [JsonIgnore] public double XpProgress
    {
        get
        {
            var n = (double)Level - 1;
            var previous = n * n * 2.5;
            var next = (n + 1) * (n + 1) * 2.5;
            return Math.Clamp((DistanceMeters - previous) / (next - previous), 0, 1);
        }
    }
    [JsonIgnore] public double MetersToNextLevel => Math.Max(0, (double)Level * Level * 2.5 - DistanceMeters);

    internal void Normalize(DateTimeOffset now)
    {
        if (!double.IsFinite(DistancePoints) || DistancePoints < 0) DistancePoints = 0;
        // A finite cap keeps downstream UI conversions and XP arithmetic bounded.
        DistancePoints = Math.Min(DistancePoints, 1e15);
        SessionCount = Math.Max(0, SessionCount);
        Streak = Math.Max(1, Streak);
        Naps = Math.Max(0, Naps);
        Scratches = Math.Max(0, Scratches);
        if (FirstLaunch == default || FirstLaunch > now) FirstLaunch = now;
    }
}
