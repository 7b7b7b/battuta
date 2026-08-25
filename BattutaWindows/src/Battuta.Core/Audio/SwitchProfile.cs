namespace Battuta.Core.Audio;

public readonly record struct SwitchProfileId
{
    public SwitchProfileId(string value)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(value);
        Value = value;
    }

    public string Value { get; }
    public override string ToString() => Value ?? string.Empty;
}

public sealed record SwitchProfileDefinition(
    SwitchProfileId Id,
    string DisplayName,
    string Family,
    string Tone,
    bool HasDedicatedSpecialKeySamples,
    bool SupportsReleaseSound,
    bool HasRowSpecificReleaseSamples);

public static class SwitchProfiles
{
    public static readonly SwitchProfileId HolyPanda = new("holypanda");
    public static readonly SwitchProfileId MxBrown = new("mxbrown");
    public static readonly SwitchProfileId MxClear = new("mxclear");
    public static readonly SwitchProfileId G915Brown = new("g915brown");
    public static readonly SwitchProfileId StudioTactile = new("studiotactile");
    public static readonly SwitchProfileId MxBlue = new("mxblue");
    public static readonly SwitchProfileId BoxNavy = new("boxnavy");
    public static readonly SwitchProfileId BoxWhite = new("boxwhite");
    public static readonly SwitchProfileId LowProfileBlue = new("lowprofileblue");
    public static readonly SwitchProfileId BlueAlps = new("bluealps");
    public static readonly SwitchProfileId StudioClicky = new("studioclicky");
    public static readonly SwitchProfileId Cream = new("cream");
    public static readonly SwitchProfileId Alpaca = new("alpaca");
    public static readonly SwitchProfileId BlackInk = new("blackink");
    public static readonly SwitchProfileId RedInk = new("redink");
    public static readonly SwitchProfileId MxBlack = new("mxblack");
    public static readonly SwitchProfileId Turquoise = new("turquoise");
    public static readonly SwitchProfileId KeychronRed = new("keychronred");
    public static readonly SwitchProfileId Topre = new("topre");
    public static readonly SwitchProfileId Buckling = new("buckling");
}

public static class SwitchProfileCatalog
{
    public static IReadOnlyList<SwitchProfileDefinition> All { get; } =
    [
        P(SwitchProfiles.HolyPanda, "Holy Panda", "段落", "饱满、集中"),
        P(SwitchProfiles.MxBrown, "Cherry MX Brown", "段落", "温和、均衡"),
        P(SwitchProfiles.MxClear, "Cherry MX Clear", "段落", "扎实、段落明显", false, true),
        P(SwitchProfiles.G915Brown, "Logitech G915 TKL Brown", "段落", "轻薄、利落", true, true),
        P(SwitchProfiles.StudioTactile, "Studio Tactile", "段落", "近场、细腻", false, true),
        P(SwitchProfiles.MxBlue, "Cherry MX Blue", "点击", "清脆、经典", false),
        P(SwitchProfiles.BoxNavy, "Kailh BOX Navy", "点击", "厚重、响亮"),
        P(SwitchProfiles.BoxWhite, "Kailh BOX White", "点击", "短促、清亮", false, true),
        P(SwitchProfiles.LowProfileBlue, "Kailh Low-profile Blue", "点击", "薄脆、双向点击", false, true),
        P(SwitchProfiles.BlueAlps, "SKCM Blue Alps", "点击", "复古、锐利"),
        P(SwitchProfiles.StudioClicky, "Studio Clicky", "点击", "明快、颗粒感", false, true),
        P(SwitchProfiles.Cream, "NovelKeys Cream", "线性", "顺滑、奶油"),
        P(SwitchProfiles.Alpaca, "Alpaca", "线性", "干净、柔和"),
        P(SwitchProfiles.BlackInk, "Gateron Black Ink", "线性", "低沉、扎实"),
        P(SwitchProfiles.RedInk, "Gateron Red Ink", "线性", "轻快、圆润"),
        P(SwitchProfiles.MxBlack, "Cherry MX Black", "线性", "沉稳、硬朗"),
        P(SwitchProfiles.Turquoise, "Turquoise Tealios", "线性", "明亮、顺滑"),
        P(SwitchProfiles.KeychronRed, "Keychron Red Linear", "线性", "干净、轻快", false, true),
        P(SwitchProfiles.Topre, "Topre", "静电容", "柔韧、闷响"),
        P(SwitchProfiles.Buckling, "IBM Buckling Spring", "屈曲弹簧", "复古、金属感"),
    ];

    private static readonly Dictionary<string, SwitchProfileDefinition> ById =
        All.ToDictionary(profile => profile.Id.Value, StringComparer.Ordinal);

    public static SwitchProfileDefinition Default => Get(SwitchProfiles.HolyPanda);

    public static bool TryGet(string? id, out SwitchProfileDefinition profile)
    {
        if (id is not null && ById.TryGetValue(id, out profile!))
        {
            return true;
        }

        profile = null!;
        return false;
    }

    public static bool TryGet(SwitchProfileId id, out SwitchProfileDefinition profile) =>
        TryGet(id.Value, out profile);

    public static SwitchProfileDefinition Get(SwitchProfileId id) =>
        TryGet(id, out var profile)
            ? profile
            : throw new KeyNotFoundException($"Unknown switch profile: {id.Value}");

    private static SwitchProfileDefinition P(
        SwitchProfileId id,
        string name,
        string family,
        string tone,
        bool dedicatedSpecial = true,
        bool rowSpecificRelease = false) =>
        new(id, name, family, tone, dedicatedSpecial, true, rowSpecificRelease);
}
