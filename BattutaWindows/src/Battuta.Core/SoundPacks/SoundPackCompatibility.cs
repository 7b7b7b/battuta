using Battuta.Core.Input;

namespace Battuta.Core.SoundPacks;

public static class SoundPackV1WireNames
{
    public static string Row(KeyboardRowId row) => row switch
    {
        KeyboardRowId.R0 => "R0",
        KeyboardRowId.R1 => "R1",
        KeyboardRowId.R2 => "R2",
        KeyboardRowId.R3 => "R3",
        KeyboardRowId.R4 => "R4",
        _ => throw new ArgumentOutOfRangeException(nameof(row)),
    };

    public static string Special(KeyboardSpecialKeyId specialKey) => specialKey switch
    {
        KeyboardSpecialKeyId.Space => "space",
        KeyboardSpecialKeyId.Enter => "enter",
        KeyboardSpecialKeyId.Backspace => "backspace",
        _ => throw new ArgumentOutOfRangeException(nameof(specialKey)),
    };
}

/// <summary>Bridges platform-neutral key IDs to the existing schema-v1 Mac IDs.</summary>
public static class SoundPackV1KeyCompatibility
{
    public static bool TryGetLegacyId(PhysicalKeyId key, out string legacyId)
    {
        if (PhysicalKeyCatalog.TryGet(key, out var definition)
            && definition.LegacySoundPackV1Id is not null)
        {
            legacyId = definition.LegacySoundPackV1Id;
            return true;
        }

        legacyId = string.Empty;
        return false;
    }

    public static bool TryGetPhysicalKey(string legacyId, out PhysicalKeyId key)
    {
        if (PhysicalKeyCatalog.TryGetByLegacySoundPackV1Id(legacyId, out var definition))
        {
            key = definition.Id;
            return true;
        }

        key = default;
        return false;
    }

    /// <summary>
    /// Legacy schema-v1 ID wins when both it and a tolerated canonical alias exist.
    /// Writers emit only the legacy ID; the canonical lookup merely makes hand-authored
    /// or future-tolerant packages useful without changing schema v1.
    /// </summary>
    public static IReadOnlyList<string> OverrideLookupIds(PhysicalKeyId key)
    {
        if (TryGetLegacyId(key, out var legacyId))
        {
            return legacyId == key.Value ? [legacyId] : [legacyId, key.Value];
        }

        return [key.Value];
    }
}
