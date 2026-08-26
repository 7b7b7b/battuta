using Battuta.Core.Audio;
using Battuta.Windows.Audio;

namespace Battuta.Windows.Tests.Audio;

public sealed class BuiltInAudioResourceCatalogTests
{
    [Fact]
    public void FullResourceTreeContainsTwentyKeyboardAndFivePointerProfiles()
    {
        var root = AudioTestFiles.FindBuiltInAudioRoot();
        var files = Directory.EnumerateFiles(root, "*.*", SearchOption.AllDirectories)
            .Where(path => Path.GetExtension(path) is ".wav" or ".mp3")
            .ToArray();

        Assert.Equal(237, files.Length);
        Assert.Equal(86, files.Count(path => Path.GetExtension(path) == ".wav"));
        Assert.Equal(151, files.Count(path => Path.GetExtension(path) == ".mp3"));
        Assert.Equal(20, SwitchProfileCatalog.All.Count);
        Assert.Equal(5, PointerSoundProfileCatalog.All.Count);
    }

    [Fact]
    public async Task EveryRequiredBuiltInResourceDecodesAndLoads()
    {
        var root = AudioTestFiles.FindBuiltInAudioRoot();
        var catalog = new BuiltInAudioResourceCatalog(root);

        foreach (var profile in SwitchProfileCatalog.All)
        {
            var bank = await catalog.LoadKeyboardBankAsync(profile);
            var expected = Enum.GetValues<KeySoundPhase>()
                .Sum(phase => BuiltInSamplePlan.RequiredSamples(profile, phase).Count);
            Assert.Equal(expected, bank.SampleCount);
        }

        foreach (var profile in PointerSoundProfileCatalog.All)
        {
            var bank = await catalog.LoadPointerBankAsync(profile);
            Assert.Equal(2, bank.SampleCount);
        }
    }

    [Fact]
    public void EveryPackagedAudioFileDecodesToFiniteCanonicalPcm()
    {
        var root = AudioTestFiles.FindBuiltInAudioRoot();
        var decoder = new PcmSampleDecoder();
        var files = Directory.EnumerateFiles(root, "*.*", SearchOption.AllDirectories)
            .Where(path => Path.GetExtension(path) is ".wav" or ".mp3")
            .ToArray();

        foreach (var file in files)
        {
            var sample = decoder.Decode(file, trimKeyboardLeadingSilence: false);
            Assert.True(sample.FrameCount > 0, file);
            Assert.All(sample.Samples.Span.ToArray(), value => Assert.True(float.IsFinite(value), file));
        }
    }

    [Fact]
    public async Task BlueAlpsLegacyLongReleaseIsPackagedButNotLoaded()
    {
        var root = AudioTestFiles.FindBuiltInAudioRoot();
        Assert.True(File.Exists(Path.Combine(root, "bluealps", "release", "GENERIC_long.mp3")));
        var catalog = new BuiltInAudioResourceCatalog(root);

        var bank = await catalog.LoadKeyboardBankAsync(
            SwitchProfileCatalog.Get(SwitchProfiles.BlueAlps));

        Assert.Equal(12, bank.SampleCount);
    }
}
