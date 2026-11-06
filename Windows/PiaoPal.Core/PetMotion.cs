namespace PiaoPal.Core;

public readonly record struct MotionSnapshot(DesktopPoint Position, PetAnimation Animation,
    SpritePose Pose, double DistancePoints, bool StartedNap = false, bool StartedScratch = false);

/// <summary>
/// Single-threaded simulation; the native shell calls this on its UI timer.
/// Coordinates are physical pixels. DistancePoints is actual travel in logical 96-DPI points.
/// Monitor re-anchoring and explicit relocation never contribute to distance.
/// </summary>
public sealed class PetMotion
{
    private enum Behavior { Idle, Reacting, Moving, Tired, Sleeping, Scratching, Waking }
    private static readonly PetAnimation[] Directions =
        [PetAnimation.E, PetAnimation.SE, PetAnimation.S, PetAnimation.SW,
         PetAnimation.W, PetAnimation.NW, PetAnimation.N, PetAnimation.NE];
    private DesktopRect[] screens = [];
    private DesktopPoint velocity;
    private Behavior behavior;
    private double behaviorElapsed;
    private int idleActionCount;
    private PetAnimation facing = PetAnimation.E;
    private double scale = 1, speed = 1, pixelsPerDip = 1;
    private string skinId = "piaopiao";

    public DesktopPoint Position { get; private set; } = new(100, 100);
    public PetAnimation Animation { get; private set; } = PetAnimation.Idle;
    public double AnimationElapsed { get; private set; }
    public double GaitPhase { get; private set; }
    public bool IsResting { get; private set; }
    public bool WalkingAtlasAvailable { get; set; } = true;
    public double Scale
    {
        get => scale;
        set { scale = double.IsFinite(value) ? Math.Clamp(value, .5, 3) : 1; Constrain(); }
    }
    public double Speed
    {
        get => speed;
        set => speed = double.IsFinite(value) ? Math.Clamp(value, .1, 4) : 1;
    }
    public double PixelsPerDip
    {
        get => pixelsPerDip;
        set { pixelsPerDip = double.IsFinite(value) ? Math.Clamp(value, .5, 8) : 1; Constrain(); }
    }
    public string SkinId
    {
        get => skinId;
        set
        {
            var next = AppSettings.IsKnownSkin(value) ? value : "piaopiao";
            if (next == skinId) return;
            skinId = next;
            velocity = default;
            Begin(IsResting ? Behavior.Sleeping : Behavior.Idle,
                IsResting ? PetAnimation.Sleeping : PetAnimation.Idle);
        }
    }
    private double Radius => 32 * Scale * PixelsPerDip;

    public void SetScreens(IEnumerable<DesktopRect> workingAreas)
    {
        ArgumentNullException.ThrowIfNull(workingAreas);
        screens = workingAreas.Where(s => s.IsValid).Distinct().ToArray();
        Constrain();
    }

    /// <summary>Preserves sleeping/resting behavior and makes no walking contribution.</summary>
    public void Relocate(DesktopPoint point)
    {
        if (!point.IsValid || screens.Length == 0) return;
        Position = NearestScreen(point).Clamp(point, Radius);
        velocity = default;
    }

    public void SetResting(bool resting)
    {
        if (IsResting == resting) return;
        IsResting = resting;
        velocity = default;
        Begin(resting ? Behavior.Tired : Behavior.Waking, PetAnimation.Tired);
    }

    public SpritePose GetPose() => SpriteAnimation.GetPose(Animation, AnimationElapsed,
        GaitPhase, SkinId, WalkingAtlasAvailable);

    public MotionSnapshot Tick(double dt, DesktopPoint cursor)
    {
        if (!double.IsFinite(dt) || dt <= 0 || !cursor.IsValid || screens.Length == 0)
            return Snapshot(0, false, false);
        Constrain();
        double distance = 0;
        bool nap = false, scratch = false;
        var targetScreen = NearestScreen(cursor);
        // Keep the companion on an actual working area when the pointer changes monitors.
        // Re-anchor across disconnected monitor gaps instead of sleeping in invisible space.
        if (!IsResting && !targetScreen.Contains(Position))
        {
            Position = targetScreen.Clamp(Position, Radius);
            velocity = default;
        }
        var target = targetScreen.Clamp(new(cursor.X, cursor.Y + 20 * PixelsPerDip), Radius);
        var remaining = Math.Min(dt, .25);
        while (remaining > .000001)
        {
            var step = Math.Min(remaining, 1.0 / 120);
            Update(step, target, targetScreen, ref distance, ref nap, ref scratch);
            remaining -= step;
        }
        return Snapshot(distance, nap, scratch);
    }

    private MotionSnapshot Snapshot(double distance, bool nap, bool scratch)
        => new(Position, Animation, GetPose(), distance, nap, scratch);

    private void Constrain()
    {
        if (screens.Length == 0) return;
        var clamped = NearestScreen(Position).Clamp(Position, Radius);
        if (clamped != Position) { Position = clamped; velocity = default; }
    }

    private DesktopRect NearestScreen(DesktopPoint point)
    {
        foreach (var screen in screens) if (screen.Contains(point)) return screen;
        return screens.MinBy(s => DesktopPoint.Distance(point, s.Clamp(point)));
    }

    private void Begin(Behavior next, PetAnimation animation)
    {
        behavior = next;
        behaviorElapsed = 0;
        Transition(animation);
    }

    private void Transition(PetAnimation animation)
    {
        if (Animation == animation) return;
        Animation = animation;
        AnimationElapsed = 0;
    }

    private void Update(double dt, DesktopPoint target, DesktopRect targetScreen,
        ref double totalDistance, ref bool nap, ref bool scratch)
    {
        AnimationElapsed = (AnimationElapsed + dt) % 86400;
        behaviorElapsed += dt;
        if (IsResting)
        {
            if (behavior != Behavior.Sleeping && behaviorElapsed >= .9)
            {
                Begin(Behavior.Sleeping, PetAnimation.Sleeping);
                nap = true;
            }
            return;
        }
        var distance = DesktopPoint.Distance(Position, target);
        var stop = 48 * PixelsPerDip;
        var start = 60 * PixelsPerDip;
        switch (behavior)
        {
            case Behavior.Moving:
                if (Advance(target, targetScreen, stop, dt, ref totalDistance))
                    Begin(Behavior.Idle, PetAnimation.Idle);
                break;
            case Behavior.Waking:
                if (behaviorElapsed >= .4) Begin(Behavior.Reacting, PetAnimation.Alert);
                break;
            case Behavior.Reacting:
                if (behaviorElapsed >= .1)
                    Begin(distance > stop ? Behavior.Moving : Behavior.Idle,
                        distance > stop ? facing : PetAnimation.Idle);
                break;
            default:
                if (distance > start)
                {
                    velocity = default;
                    var waking = behavior is Behavior.Sleeping or Behavior.Tired;
                    Begin(waking ? Behavior.Waking : Behavior.Reacting,
                        waking ? PetAnimation.Tired : PetAnimation.Alert);
                    return;
                }
                switch (behavior)
                {
                    case Behavior.Idle when behaviorElapsed >= 10:
                        idleActionCount++;
                        if (idleActionCount % 2 == 1)
                        { Begin(Behavior.Scratching, PetAnimation.ScratchSelf); scratch = true; }
                        else Begin(Behavior.Tired, PetAnimation.Tired);
                        break;
                    case Behavior.Scratching when behaviorElapsed >= 1.2:
                        Begin(Behavior.Idle, PetAnimation.Idle);
                        break;
                    case Behavior.Tired when behaviorElapsed >= .9:
                        Begin(Behavior.Sleeping, PetAnimation.Sleeping); nap = true;
                        break;
                    case Behavior.Sleeping when behaviorElapsed >= 22:
                        Begin(Behavior.Waking, PetAnimation.Tired);
                        break;
                }
                break;
        }
    }

    private bool Advance(DesktopPoint target, DesktopRect screen, double stoppingRadius,
        double dt, ref double totalDistance)
    {
        var dx = target.X - Position.X;
        var dy = target.Y - Position.Y;
        var distance = Math.Sqrt(dx * dx + dy * dy);
        var available = Math.Max(0, distance - stoppingRadius);
        if (available <= .25 * PixelsPerDip) { velocity = default; return true; }
        var acceleration = 1600 * Speed * PixelsPerDip;
        var desiredSpeed = Math.Min(160 * Speed * PixelsPerDip,
            Math.Min(Math.Sqrt(2 * acceleration * available), available * 12));
        var vx = dx / distance * desiredSpeed;
        var vy = dy / distance * desiredSpeed;
        var changeX = vx - velocity.X;
        var changeY = vy - velocity.Y;
        var change = Math.Sqrt(changeX * changeX + changeY * changeY);
        var factor = change > acceleration * dt ? acceleration * dt / change : 1;
        velocity = new(velocity.X + changeX * factor, velocity.Y + changeY * factor);
        var moveX = velocity.X * dt;
        var moveY = velocity.Y * dt;
        var proposedDistance = Math.Sqrt(moveX * moveX + moveY * moveY);
        if (proposedDistance > available)
        { moveX *= available / proposedDistance; moveY *= available / proposedDistance; }
        var next = screen.Clamp(new(Position.X + moveX, Position.Y + moveY), Radius);
        var actualDistance = DesktopPoint.Distance(Position, next);
        if (actualDistance <= .00001)
        {
            velocity = default;
            return proposedDistance > .00001;
        }
        Position = next;
        totalDistance += actualDistance / PixelsPerDip;
        GaitPhase = (GaitPhase + Math.Min(actualDistance / (20 * Scale * PixelsPerDip), dt * 5)) % 1;
        UpdateFacing(velocity);
        Transition(facing);
        return false;
    }

    private void UpdateFacing(DesktopPoint direction)
    {
        if (Math.Sqrt(direction.X * direction.X + direction.Y * direction.Y) <= PixelsPerDip) return;
        var angle = Math.Atan2(direction.Y, direction.X);
        var sector = Math.PI / 4;
        var current = Array.IndexOf(Directions, facing);
        var difference = Math.Atan2(Math.Sin(angle - current * sector), Math.Cos(angle - current * sector));
        if (Math.Abs(difference) <= sector / 2 + 8 * Math.PI / 180) return;
        var index = ((int)Math.Round(angle / sector, MidpointRounding.AwayFromZero) + 8) % 8;
        facing = Directions[index];
    }
}
