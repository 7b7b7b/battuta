using Battuta.Core.Audio;

namespace Battuta.Core.Tests.Audio;

public sealed class BundledAudioResourceContractTests
{
    [Fact]
    public void MacAudioTreeContainsEverySampleRequiredByWindowsCore()
    {
        var repositoryRoot = FindRepositoryRoot();
        var audioRoot = Path.Combine(
            repositoryRoot,
            "SimuBoardMac",
            "SimuBoardMac",
            "Resources",
            "Audio");
        var actual = Directory.EnumerateFiles(audioRoot, "*.*", SearchOption.AllDirectories)
            .Where(path => Path.GetExtension(path) is ".wav" or ".mp3")
            .Select(path => Path.GetRelativePath(audioRoot, path).Replace('\\', '/'))
            .ToHashSet(StringComparer.Ordinal);

        var required = new HashSet<string>(StringComparer.Ordinal);
        foreach (var profile in SwitchProfileCatalog.All)
        {
            foreach (var phase in Enum.GetValues<KeySoundPhase>())
            {
                foreach (var sample in BuiltInSamplePlan.RequiredSamples(profile, phase))
                {
                    var stem = $"{profile.Id.Value}/{phase.DirectoryName()}/{sample.ResourceName()}";
                    var matches = actual.Where(path =>
                        path == $"{stem}.wav" || path == $"{stem}.mp3").ToArray();
                    Assert.Single(matches);
                    required.Add(matches[0]);
                }
            }
        }

        foreach (var profile in PointerSoundProfileCatalog.All)
        {
            foreach (var phase in Enum.GetValues<PointerSoundPhase>())
            {
                var phaseName = phase == PointerSoundPhase.Press ? "press" : "release";
                var path = $"pointer/{profile.Id.Value}/{phaseName}/PRIMARY.wav";
                Assert.Contains(path, actual);
                required.Add(path);
            }
        }

        Assert.Equal(236, required.Count);
        Assert.Equal(237, actual.Count);
        Assert.Equal(
            ["bluealps/release/GENERIC_long.mp3"],
            actual.Except(required, StringComparer.Ordinal));
    }

    private static string FindRepositoryRoot()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null)
        {
            if (Directory.Exists(Path.Combine(directory.FullName, "SimuBoardMac")))
            {
                return directory.FullName;
            }

            directory = directory.Parent;
        }

        throw new DirectoryNotFoundException("Could not locate the Battuta repository root.");
    }
}
