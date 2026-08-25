using Battuta.Core.Audio;

namespace Battuta.Core.Tests.Audio;

public sealed class PlaybackVariantCycleTests
{
    [Fact]
    public void RecipesAreBalancedSubtleAndIncludeOriginal()
    {
        Assert.Equal(4, PlaybackVariantCycle.Variants.Count);
        Assert.Equal(4, PlaybackVariantCycle.Variants.Distinct().Count());
        Assert.Contains(PlaybackVariant.Original, PlaybackVariantCycle.Variants);
        Assert.All(PlaybackVariantCycle.Variants, variant =>
        {
            Assert.InRange(variant.Gain, 0.9f, 1.1f);
            Assert.InRange(variant.Rate, 0.95f, 1.05f);
        });

        Assert.All(PlaybackVariantCycle.Variants.Select((_, index) => index), index =>
            Assert.Equal(
                PlaybackVariantCycle.PlaybackOrder.Count / PlaybackVariantCycle.Variants.Count,
                PlaybackVariantCycle.PlaybackOrder.Count(value => value == index)));
    }

    [Fact]
    public void RotationNeverRepeatsConsecutivelyAndExposesEveryVariant()
    {
        var cycle = new PlaybackVariantCycle();
        PlaybackVariant? prior = null;
        var observed = new HashSet<PlaybackVariant>();

        for (var index = 0; index < PlaybackVariantCycle.PlaybackOrder.Count * 3; index++)
        {
            var next = cycle.Next(true);
            Assert.NotEqual(prior, next);
            observed.Add(next);
            prior = next;
        }

        Assert.Equal(PlaybackVariantCycle.Variants.ToHashSet(), observed);
    }

    [Fact]
    public void DisabledVariationReturnsOriginalWithoutConsumingRotation()
    {
        var cycle = new PlaybackVariantCycle();
        var first = cycle.Next(true);
        var disabled = cycle.Next(false);
        var resumed = cycle.Next(true);

        Assert.Equal(PlaybackVariant.Original, first);
        Assert.Equal(PlaybackVariant.Original, disabled);
        Assert.Equal(
            PlaybackVariantCycle.Variants[PlaybackVariantCycle.PlaybackOrder[1]],
            resumed);
    }
}
