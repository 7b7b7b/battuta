namespace Battuta.Core.Audio;

public readonly record struct PlaybackVariant(float Gain, float Rate)
{
    public static readonly PlaybackVariant Original = new(1, 1);
}

public struct PlaybackVariantCycle
{
    public static IReadOnlyList<PlaybackVariant> Variants { get; } =
    [
        PlaybackVariant.Original,
        new(0.975f, 0.978f),
        new(0.99f, 1.018f),
        new(1.02f, 0.992f),
    ];

    public static IReadOnlyList<int> PlaybackOrder { get; } =
    [
        0, 2, 1, 3,
        1, 0, 3, 2,
        3, 1, 2, 0,
        2, 3, 0, 1,
    ];

    public int Cursor { get; private set; }

    public PlaybackVariant Next(bool variationEnabled)
    {
        if (!variationEnabled)
        {
            return PlaybackVariant.Original;
        }

        var variant = Variants[PlaybackOrder[Cursor]];
        Cursor = (Cursor + 1) % PlaybackOrder.Count;
        return variant;
    }
}
