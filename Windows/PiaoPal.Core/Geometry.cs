namespace PiaoPal.Core;

/// <summary>Physical desktop pixels, including negative coordinates on secondary displays.</summary>
public readonly record struct DesktopPoint(double X, double Y)
{
    internal const double CoordinateLimit = 10_000_000;
    public bool IsValid => double.IsFinite(X) && double.IsFinite(Y)
        && Math.Abs(X) <= CoordinateLimit && Math.Abs(Y) <= CoordinateLimit;
    public static double Distance(DesktopPoint a, DesktopPoint b)
        => Math.Sqrt((a.X - b.X) * (a.X - b.X) + (a.Y - b.Y) * (a.Y - b.Y));
}

/// <summary>An actual monitor working area, not a union containing invisible gaps.</summary>
public readonly record struct DesktopRect(double X, double Y, double Width, double Height)
{
    public double Right => X + Width;
    public double Bottom => Y + Height;
    public bool IsValid => new DesktopPoint(X, Y).IsValid
        && double.IsFinite(Width) && double.IsFinite(Height) && Width > 0 && Height > 0
        && Width <= DesktopPoint.CoordinateLimit && Height <= DesktopPoint.CoordinateLimit
        && new DesktopPoint(Right, Bottom).IsValid;
    public bool Contains(DesktopPoint point) => IsValid && point.IsValid
        && point.X >= X && point.X <= Right && point.Y >= Y && point.Y <= Bottom;
    public DesktopPoint Clamp(DesktopPoint point, double radius = 0)
    {
        var rx = Math.Min(Math.Max(0, radius), Width / 2);
        var ry = Math.Min(Math.Max(0, radius), Height / 2);
        return new(Math.Clamp(point.X, X + rx, Right - rx),
                   Math.Clamp(point.Y, Y + ry, Bottom - ry));
    }
}

/// <summary>
/// Screen position of a layered window. Values that do not fit in a Win32 POINT
/// used to be cast and then failed UpdateLayeredWindow, which terminated the pet.
/// </summary>
public static class LayeredFramePlacement
{
    public static bool TryOrigin(double left, double top, int width, int height, out int x, out int y)
    {
        x = 0;
        y = 0;
        if (width <= 0 || height <= 0 || width > 4096 || height > 4096) return false;
        if (!IsWindowCoordinate(left) || !IsWindowCoordinate(top)) return false;
        x = (int)Math.Round(left);
        y = (int)Math.Round(top);
        return true;
    }

    private static bool IsWindowCoordinate(double value)
        => double.IsFinite(value) && value > int.MinValue && value < int.MaxValue;
}
