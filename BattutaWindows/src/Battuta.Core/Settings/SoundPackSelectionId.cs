using Battuta.Core.Audio;

namespace Battuta.Core.Settings;

public enum SoundPackSelectionKind
{
    BuiltIn,
    Custom,
}

public readonly record struct SoundPackSelectionId
{
    private const string CustomPrefix = "custom:";

    private SoundPackSelectionId(string value, SoundPackSelectionKind kind, Guid? customPackId)
    {
        Value = value;
        Kind = kind;
        CustomPackId = customPackId;
    }

    public string Value { get; }
    public SoundPackSelectionKind Kind { get; }
    public Guid? CustomPackId { get; }

    public static SoundPackSelectionId Default => FromBuiltIn(SwitchProfiles.HolyPanda);

    public static SoundPackSelectionId FromBuiltIn(SwitchProfileId profileId)
    {
        if (!SwitchProfileCatalog.TryGet(profileId, out _))
        {
            throw new ArgumentException($"Unknown built-in sound profile: {profileId.Value}", nameof(profileId));
        }

        return new SoundPackSelectionId(profileId.Value, SoundPackSelectionKind.BuiltIn, null);
    }

    public static SoundPackSelectionId FromCustom(Guid packId) =>
        new($"{CustomPrefix}{packId:D}".ToLowerInvariant(), SoundPackSelectionKind.Custom, packId);

    public static bool TryParse(string? value, out SoundPackSelectionId selection)
    {
        if (SwitchProfileCatalog.TryGet(value, out var profile))
        {
            selection = FromBuiltIn(profile.Id);
            return true;
        }

        if (value is not null
            && value.StartsWith(CustomPrefix, StringComparison.Ordinal)
            && Guid.TryParseExact(value[CustomPrefix.Length..], "D", out var packId))
        {
            selection = FromCustom(packId);
            return true;
        }

        selection = default;
        return false;
    }

    public override string ToString() => Value ?? string.Empty;
}
