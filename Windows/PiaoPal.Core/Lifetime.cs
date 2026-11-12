namespace PiaoPal.Core;

public enum CompanionLifetimeEvent
{
    Suspend,
    Resume,
    Lock,
    Unlock,
    Logoff,
    Other
}

/// <summary>
/// What the shell should do for sleep, lock, and logoff. Saving is required on the
/// way down so a power loss during sleep does not drop the last interval.
/// </summary>
public readonly record struct LifetimeReaction(bool SuspendRendering, bool ResumeRendering, bool SaveStats);

public static class CompanionLifetime
{
    public static LifetimeReaction React(CompanionLifetimeEvent kind) => kind switch
    {
        CompanionLifetimeEvent.Suspend or CompanionLifetimeEvent.Lock or CompanionLifetimeEvent.Logoff
            => new(true, false, true),
        CompanionLifetimeEvent.Resume or CompanionLifetimeEvent.Unlock
            => new(false, true, false),
        _ => new(false, false, false)
    };
}
