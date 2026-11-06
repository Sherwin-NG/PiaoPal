namespace PiaoPal.Core;

public enum PetAnimation
{
    Idle, Alert, Tired, Sleeping, ScratchSelf,
    ScratchWallN, ScratchWallS, ScratchWallE, ScratchWallW,
    N, NE, E, SE, S, SW, W, NW
}

public readonly record struct SpritePose(int Column, int Row, int Columns, int Rows,
    bool UsesWalkingAtlas = false, double BreathScale = 1);

public static class SpriteAnimation
{
    private static readonly Dictionary<PetAnimation, (int Column, int Row)[]> Frames = new()
    {
        [PetAnimation.Idle] = [(3, 3)], [PetAnimation.Alert] = [(7, 3)],
        [PetAnimation.ScratchSelf] = [(5, 0), (6, 0), (7, 0)],
        [PetAnimation.ScratchWallN] = [(0, 0), (0, 1)],
        [PetAnimation.ScratchWallS] = [(7, 1), (6, 2)],
        [PetAnimation.ScratchWallE] = [(2, 2), (2, 3)],
        [PetAnimation.ScratchWallW] = [(4, 0), (4, 1)],
        [PetAnimation.Tired] = [(3, 2)], [PetAnimation.Sleeping] = [(2, 0), (2, 1)],
        [PetAnimation.N] = [(1, 2), (1, 3)], [PetAnimation.NE] = [(0, 2), (0, 3)],
        [PetAnimation.E] = [(3, 0), (3, 1)], [PetAnimation.SE] = [(5, 1), (5, 2)],
        [PetAnimation.S] = [(6, 3), (7, 2)], [PetAnimation.SW] = [(5, 3), (6, 1)],
        [PetAnimation.W] = [(4, 2), (4, 3)], [PetAnimation.NW] = [(1, 0), (1, 1)],
    };
    private static readonly PetAnimation[] WalkingDirections =
        [PetAnimation.N, PetAnimation.NE, PetAnimation.E, PetAnimation.SE,
         PetAnimation.S, PetAnimation.SW, PetAnimation.W, PetAnimation.NW];

    public static SpritePose GetPose(PetAnimation animation, double elapsed, double gaitPhase,
        string skinId, bool walkingAtlasAvailable = true)
    {
        elapsed = double.IsFinite(elapsed) && elapsed >= 0 ? elapsed : 0;
        var phase = double.IsFinite(gaitPhase) && gaitPhase >= 0 ? gaitPhase % 1 : 0;
        var piaopiao = skinId == "piaopiao";
        var row = Array.IndexOf(WalkingDirections, animation);
        if (piaopiao && row >= 0)
        {
            if (walkingAtlasAvailable) return new(Math.Min(3, (int)(phase * 4)), row, 4, 8, true);
            var legacyFrame = Frames[animation][Math.Min(1, (int)(phase * 2))];
            return new(legacyFrame.Column, legacyFrame.Row, 8, 4);
        }
        if (piaopiao && animation is PetAnimation.Idle or PetAnimation.Sleeping)
        {
            var sleeping = animation == PetAnimation.Sleeping;
            var period = sleeping ? 4.4 : 4.8;
            var breath = (1 - Math.Cos(2 * Math.PI * (elapsed % period) / period)) / 2;
            var fixedFrame = Frames[animation][0];
            return new(fixedFrame.Column, fixedFrame.Row, 8, 4, false,
                1 + breath * (sleeping ? .012 : .008));
        }
        var frames = Frames.GetValueOrDefault(animation, Frames[PetAnimation.Idle]);
        var interval = piaopiao ? (animation == PetAnimation.ScratchSelf ? .16 : .18)
            : (animation == PetAnimation.Sleeping ? .4 : .1);
        // Modulo before division keeps even enormous finite elapsed values convertible to int.
        var index = Math.Min(frames.Length - 1, (int)((elapsed % (interval * frames.Length)) / interval));
        var frame = frames[index];
        return new(frame.Column, frame.Row, 8, 4);
    }
}
