namespace Battuta.Core.Audio;

public enum PointerSoundPhase
{
    Press,
    Release,
}

public enum PointerSoundSample
{
    Primary,
    Secondary,
    Middle,
}

public enum PointerButtonKind
{
    Primary,
    Secondary,
    Middle,
    Auxiliary,
}

public readonly record struct PointerButton
{
    private PointerButton(PointerButtonKind kind, long auxiliaryNumber)
    {
        Kind = kind;
        AuxiliaryNumber = auxiliaryNumber;
    }

    public PointerButtonKind Kind { get; }
    public long AuxiliaryNumber { get; }

    public static PointerButton Primary => new(PointerButtonKind.Primary, 0);
    public static PointerButton Secondary => new(PointerButtonKind.Secondary, 1);
    public static PointerButton Middle => new(PointerButtonKind.Middle, 2);
    public static PointerButton Auxiliary(long number) => new(PointerButtonKind.Auxiliary, number);

    public static PointerButton FromButtonNumber(long number) => number switch
    {
        0 => Primary,
        1 => Secondary,
        2 => Middle,
        _ => Auxiliary(number),
    };

    public PointerSoundSample Sample => Kind switch
    {
        PointerButtonKind.Primary => PointerSoundSample.Primary,
        PointerButtonKind.Secondary => PointerSoundSample.Secondary,
        PointerButtonKind.Middle or PointerButtonKind.Auxiliary => PointerSoundSample.Middle,
        _ => PointerSoundSample.Primary,
    };

    public float PlaybackRate => Kind switch
    {
        PointerButtonKind.Primary => 1,
        PointerButtonKind.Secondary => 0.97f,
        PointerButtonKind.Middle => 1.04f,
        PointerButtonKind.Auxiliary => 1.02f,
        _ => 1,
    };
}

public readonly record struct PointerSoundProfileId
{
    public PointerSoundProfileId(string value)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(value);
        Value = value;
    }

    public string Value { get; }
    public override string ToString() => Value ?? string.Empty;
}

public sealed record PointerSoundProfileDefinition(
    PointerSoundProfileId Id,
    string DisplayName,
    string Family,
    string Tone);

public static class PointerSoundProfiles
{
    public static readonly PointerSoundProfileId Classic = new("classic");
    public static readonly PointerSoundProfileId Silent = new("silent");
    public static readonly PointerSoundProfileId Crisp = new("crisp");
    public static readonly PointerSoundProfileId Heavy = new("heavy");
    public static readonly PointerSoundProfileId Glass = new("glass");
}

public static class PointerSoundProfileCatalog
{
    public static IReadOnlyList<PointerSoundProfileDefinition> All { get; } =
    [
        new(PointerSoundProfiles.Classic, "经典微动", "通用鼠标", "清晰、均衡"),
        new(PointerSoundProfiles.Silent, "静音微动", "静音鼠标", "柔和、低调"),
        new(PointerSoundProfiles.Crisp, "电竞脆响", "轻快点击", "短促、明亮"),
        new(PointerSoundProfiles.Heavy, "厚重办公", "办公鼠标", "低沉、扎实"),
        new(PointerSoundProfiles.Glass, "玻璃触控板", "触控板", "干净、通透"),
    ];

    private static readonly Dictionary<string, PointerSoundProfileDefinition> ById =
        All.ToDictionary(profile => profile.Id.Value, StringComparer.Ordinal);

    public static PointerSoundProfileDefinition Default => Get(PointerSoundProfiles.Classic);

    public static bool TryGet(string? id, out PointerSoundProfileDefinition profile)
    {
        if (id is not null && ById.TryGetValue(id, out profile!))
        {
            return true;
        }

        profile = null!;
        return false;
    }

    public static PointerSoundProfileDefinition Get(PointerSoundProfileId id) =>
        TryGet(id.Value, out var profile)
            ? profile
            : throw new KeyNotFoundException($"Unknown pointer profile: {id.Value}");
}
