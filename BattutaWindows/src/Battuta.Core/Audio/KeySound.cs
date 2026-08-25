using Battuta.Core.Input;

namespace Battuta.Core.Audio;

public enum KeySoundPhase
{
    Press,
    Release,
}

public enum KeySoundSample
{
    GenericR0,
    GenericR1,
    GenericR2,
    GenericR3,
    GenericR4,
    Generic,
    Space,
    Enter,
    Backspace,
}

public static class KeySoundWireNames
{
    public static string ResourceName(this KeySoundSample sample) => sample switch
    {
        KeySoundSample.GenericR0 => "GENERIC_R0",
        KeySoundSample.GenericR1 => "GENERIC_R1",
        KeySoundSample.GenericR2 => "GENERIC_R2",
        KeySoundSample.GenericR3 => "GENERIC_R3",
        KeySoundSample.GenericR4 => "GENERIC_R4",
        KeySoundSample.Generic => "GENERIC",
        KeySoundSample.Space => "SPACE",
        KeySoundSample.Enter => "ENTER",
        KeySoundSample.Backspace => "BACKSPACE",
        _ => throw new ArgumentOutOfRangeException(nameof(sample)),
    };

    public static string DirectoryName(this KeySoundPhase phase) => phase switch
    {
        KeySoundPhase.Press => "press",
        KeySoundPhase.Release => "release",
        _ => throw new ArgumentOutOfRangeException(nameof(phase)),
    };
}

public static class KeySoundMapper
{
    public static KeySoundSample? SampleFor(
        PhysicalKeyId key,
        KeySoundPhase phase,
        SwitchProfileDefinition profile)
    {
        var special = PhysicalKeyCatalog.SpecialKeyFor(key) switch
        {
            KeyboardSpecialKeyId.Space => KeySoundSample.Space,
            KeyboardSpecialKeyId.Enter => KeySoundSample.Enter,
            KeyboardSpecialKeyId.Backspace => KeySoundSample.Backspace,
            _ => (KeySoundSample?)null,
        };

        if (phase == KeySoundPhase.Release)
        {
            if (!profile.SupportsReleaseSound)
            {
                return null;
            }

            if (profile.HasDedicatedSpecialKeySamples && special.HasValue)
            {
                return special.Value;
            }

            return profile.HasRowSpecificReleaseSamples
                ? GenericSample(PhysicalKeyCatalog.RowFor(key))
                : KeySoundSample.Generic;
        }

        if (profile.HasDedicatedSpecialKeySamples && special.HasValue)
        {
            return special.Value;
        }

        return GenericSample(PhysicalKeyCatalog.RowFor(key));
    }

    public static KeySoundSample GenericSample(KeyboardRowId row) => row switch
    {
        KeyboardRowId.R0 => KeySoundSample.GenericR0,
        KeyboardRowId.R1 => KeySoundSample.GenericR1,
        KeyboardRowId.R2 => KeySoundSample.GenericR2,
        KeyboardRowId.R3 => KeySoundSample.GenericR3,
        KeyboardRowId.R4 => KeySoundSample.GenericR4,
        _ => KeySoundSample.GenericR4,
    };
}

public static class BuiltInSamplePlan
{
    private static readonly KeySoundSample[] RowSamples =
    [
        KeySoundSample.GenericR0,
        KeySoundSample.GenericR1,
        KeySoundSample.GenericR2,
        KeySoundSample.GenericR3,
        KeySoundSample.GenericR4,
    ];

    private static readonly KeySoundSample[] SpecialSamples =
        [KeySoundSample.Space, KeySoundSample.Enter, KeySoundSample.Backspace];

    public static IReadOnlyList<KeySoundSample> RequiredSamples(
        SwitchProfileDefinition profile,
        KeySoundPhase phase)
    {
        if (phase == KeySoundPhase.Press)
        {
            return profile.HasDedicatedSpecialKeySamples
                ? [.. RowSamples, .. SpecialSamples]
                : RowSamples;
        }

        if (!profile.SupportsReleaseSound)
        {
            return [];
        }

        if (profile.HasRowSpecificReleaseSamples)
        {
            return profile.HasDedicatedSpecialKeySamples
                ? [.. RowSamples, .. SpecialSamples]
                : RowSamples;
        }

        return profile.HasDedicatedSpecialKeySamples
            ? [KeySoundSample.Generic, .. SpecialSamples]
            : [KeySoundSample.Generic];
    }
}
