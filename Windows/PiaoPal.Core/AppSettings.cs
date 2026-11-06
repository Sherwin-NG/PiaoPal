namespace PiaoPal.Core;

public sealed class AppSettings
{
    public static readonly string[] SkinIds = ["piaopiao", "classic", "dog", "tora", "maia", "vaporwave"];
    public string SkinId { get; set; } = "piaopiao";
    public string Nickname { get; set; } = "";
    public double Scale { get; set; } = 1;
    public double Speed { get; set; } = 1;
    public string Language { get; set; } = "zh-CN";

    public static bool IsKnownSkin(string? id) => id is not null && Array.IndexOf(SkinIds, id) >= 0;

    internal void Normalize()
    {
        if (!IsKnownSkin(SkinId)) SkinId = "piaopiao";
        Nickname = (Nickname ?? "").Trim();
        if (Nickname.Length > 40) Nickname = Nickname[..40];
        Scale = double.IsFinite(Scale) ? Math.Clamp(Scale, .5, 3) : 1;
        Speed = double.IsFinite(Speed) && (Math.Abs(Speed - .4) < .0001
            || Math.Abs(Speed - 1) < .0001 || Math.Abs(Speed - 2.5) < .0001) ? Speed : 1;
        if (Language is not ("zh-CN" or "en")) Language = "zh-CN";
    }
}
