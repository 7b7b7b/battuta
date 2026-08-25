using Battuta.Core.Audio;
using Battuta.Core.SoundPacks;
using Battuta.Windows.Audio;
using Battuta.Windows.Diy.Packages;
using Battuta.Windows.Runtime;
using Battuta.Windows.Tests.Audio;

namespace Battuta.Windows.Tests.Runtime;

public sealed class SoundPackRuntimeControllerTests
{
    [Fact]
    public async Task CustomSelectionLoadsDocumentAndCommitsCustomBank()
    {
        var root = NewTemporaryRoot();
        try
        {
            var baseProfile = SwitchProfileCatalog.Default;
            AudioTestFiles.CreateKeyboardProfile(root, baseProfile, Enumerable.Repeat(0.1f, 480).ToArray());
            var document = CreateCustomDocument(root, baseProfile, writeAsset: true);
            var mixer = new PolyphonicSampleProvider();
            var engine = new KeyboardAudioEngine(mixer, new BuiltInAudioResourceCatalog(root));
            await using var controller = new SoundPackRuntimeController(
                engine,
                (id, _) => Task.FromResult(id == document.Manifest.Id
                    ? document
                    : throw new InvalidOperationException("Unexpected pack ID.")));

            var result = await controller.ActivateAsync(document.Descriptor.SelectionId);

            Assert.True(result.LoadedRequestedSelection);
            Assert.False(result.WasSuperseded);
            Assert.Null(result.Error);
            Assert.Equal(document.Descriptor.SelectionId, controller.ActiveSelectionId);
            Assert.Null(controller.Error);
        }
        finally
        {
            DeleteTemporaryRoot(root);
        }
    }

    [Fact]
    public async Task MissingCustomPackageFallsBackToHolyPandaAndPublishesError()
    {
        var root = NewTemporaryRoot();
        try
        {
            AudioTestFiles.CreateKeyboardProfile(
                root,
                SwitchProfileCatalog.Default,
                Enumerable.Repeat(0.1f, 480).ToArray());
            var mixer = new PolyphonicSampleProvider();
            var engine = new KeyboardAudioEngine(mixer, new BuiltInAudioResourceCatalog(root));
            await using var controller = new SoundPackRuntimeController(
                engine,
                (_, _) => throw new SoundPackException(
                    SoundPackErrorKind.PackNotFound,
                    "Package is missing."));
            var selection = $"custom:{Guid.NewGuid():D}";

            var result = await controller.ActivateAsync(selection);

            Assert.False(result.LoadedRequestedSelection);
            Assert.Equal(SwitchProfiles.HolyPanda.Value, result.ActiveSelectionId);
            Assert.Contains("Holy Panda", result.Error, StringComparison.Ordinal);
            Assert.Contains("Package is missing", controller.Error, StringComparison.Ordinal);

            var recovered = await controller.ActivateAsync(SwitchProfiles.HolyPanda.Value);
            Assert.True(recovered.LoadedRequestedSelection);
            Assert.Null(controller.Error);
        }
        finally
        {
            DeleteTemporaryRoot(root);
        }
    }

    [Fact]
    public async Task BrokenCustomAudioFallsBackToManifestBaseProfile()
    {
        var root = NewTemporaryRoot();
        try
        {
            var baseProfile = SwitchProfileCatalog.Get(SwitchProfiles.MxBrown);
            AudioTestFiles.CreateKeyboardProfile(root, baseProfile, Enumerable.Repeat(0.1f, 480).ToArray());
            var document = CreateCustomDocument(root, baseProfile, writeAsset: false);
            var mixer = new PolyphonicSampleProvider();
            var engine = new KeyboardAudioEngine(mixer, new BuiltInAudioResourceCatalog(root));
            await using var controller = new SoundPackRuntimeController(
                engine,
                (_, _) => Task.FromResult(document));

            var result = await controller.ActivateAsync(document.Descriptor.SelectionId);

            Assert.False(result.LoadedRequestedSelection);
            Assert.Equal(SwitchProfiles.MxBrown.Value, result.ActiveSelectionId);
            Assert.Contains(baseProfile.DisplayName, result.Error, StringComparison.Ordinal);
            Assert.NotNull(controller.Error);
        }
        finally
        {
            DeleteTemporaryRoot(root);
        }
    }

    [Fact]
    public async Task LaterBuiltInSelectionCancelsObsoleteCustomLoad()
    {
        var root = NewTemporaryRoot();
        try
        {
            var builtIn = SwitchProfileCatalog.Get(SwitchProfiles.MxBrown);
            AudioTestFiles.CreateKeyboardProfile(root, builtIn, Enumerable.Repeat(0.1f, 480).ToArray());
            var loadStarted = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            var mixer = new PolyphonicSampleProvider();
            var engine = new KeyboardAudioEngine(mixer, new BuiltInAudioResourceCatalog(root));
            await using var controller = new SoundPackRuntimeController(
                engine,
                async (_, cancellationToken) =>
                {
                    loadStarted.TrySetResult();
                    await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
                    throw new InvalidOperationException("Unreachable");
                });
            var obsolete = controller.ActivateAsync($"custom:{Guid.NewGuid():D}");
            await loadStarted.Task.WaitAsync(TimeSpan.FromSeconds(1));

            var current = await controller.ActivateAsync(builtIn.Id.Value);
            var obsoleteResult = await obsolete;

            Assert.True(current.LoadedRequestedSelection);
            Assert.True(obsoleteResult.WasSuperseded);
            Assert.Equal(builtIn.Id.Value, controller.ActiveSelectionId);
            Assert.Null(controller.Error);
        }
        finally
        {
            DeleteTemporaryRoot(root);
        }
    }

    private static DiySoundPackDocument CreateCustomDocument(
        string audioRoot,
        SwitchProfileDefinition baseProfile,
        bool writeAsset)
    {
        var packageRoot = Path.Combine(audioRoot, $"package-{Guid.NewGuid():N}.simuboardpack");
        var assetId = new SoundPackAssetId(new string('b', 64));
        var assetRelativePath = $"assets/{assetId.Value}.wav";
        var assetPath = Path.Combine(packageRoot, "assets", assetId.Value + ".wav");
        if (writeAsset)
        {
            AudioTestFiles.WriteMonoPcm16Wave(assetPath, Enumerable.Repeat(0.6f, 480).ToArray());
        }

        var manifest = new SoundPackManifest
        {
            Id = Guid.NewGuid(),
            Name = "Runtime custom fixture",
            BaseProfileId = baseProfile.Id.Value,
            Press = new SoundPackPhaseAssignments { Generic = assetId },
            Assets = new Dictionary<string, SoundPackAudioAsset>(StringComparer.Ordinal)
            {
                [assetId.Value] = new SoundPackAudioAsset
                {
                    Id = assetId,
                    RelativePath = assetRelativePath,
                    Sha256 = assetId.Value,
                    DurationSeconds = 0.01,
                    SampleRate = 48_000,
                    ChannelCount = 1,
                    ByteCount = 1_004,
                },
            },
        };
        return new DiySoundPackDocument(
            SoundPackDescriptors.Custom(manifest),
            manifest,
            packageRoot);
    }

    private static string NewTemporaryRoot()
    {
        var root = Path.Combine(Path.GetTempPath(), $"battuta-runtime-sound-pack-{Guid.NewGuid():N}");
        Directory.CreateDirectory(root);
        return root;
    }

    private static void DeleteTemporaryRoot(string root)
    {
        if (Directory.Exists(root))
        {
            Directory.Delete(root, recursive: true);
        }
    }
}
