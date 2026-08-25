using Battuta.Core.Audio;
using Battuta.Core.Input;
using Battuta.Windows.Diy.ViewModels;

namespace Battuta.Windows.Audio;

/// <summary>Connects the DIY editor's preview button to the same preloaded realtime mixer.</summary>
public sealed class DiyAudioPreviewService : IDiyAudioPreviewService
{
    private readonly KeyboardAudioEngine engine;
    private readonly PcmSampleDecoder decoder;
    private readonly Func<double> volumeProvider;

    public DiyAudioPreviewService(
        KeyboardAudioEngine engine,
        PcmSampleDecoder? decoder = null,
        Func<double>? volumeProvider = null)
    {
        this.engine = engine ?? throw new ArgumentNullException(nameof(engine));
        this.decoder = decoder ?? new PcmSampleDecoder();
        this.volumeProvider = volumeProvider ?? (() => 0.42);
    }

    public async Task PreviewAsync(
        string audioPath,
        CancellationToken cancellationToken = default)
    {
        var sample = await decoder
            .DecodeAsync(audioPath, trimKeyboardLeadingSilence: false, cancellationToken)
            .ConfigureAwait(false);
        cancellationToken.ThrowIfCancellationRequested();
        if (!engine.Preview(sample, volumeProvider()))
        {
            throw new InvalidOperationException("Audio preview could not be queued for playback.");
        }
    }
}

/// <summary>Lets the DIY editor preview the exact built-in sample selected by the Core key mapper.</summary>
public sealed class DiyBuiltInAudioLocator(BuiltInAudioResourceCatalog resources)
    : IDiyBuiltInAudioLocator
{
    private readonly BuiltInAudioResourceCatalog resources =
        resources ?? throw new ArgumentNullException(nameof(resources));

    public string? FindAudio(string profileId, PhysicalKeyId key, KeySoundPhase phase)
    {
        if (!SwitchProfileCatalog.TryGet(profileId, out var profile))
        {
            return null;
        }

        var requested = KeySoundMapper.SampleFor(key, phase, profile);
        if (requested is null)
        {
            return null;
        }

        try
        {
            return resources.ResolveKeyboardResource(profile, phase, requested.Value);
        }
        catch (FileNotFoundException)
        {
            var fallback = phase == KeySoundPhase.Release
                ? profile.HasRowSpecificReleaseSamples
                    ? KeySoundSample.GenericR2
                    : KeySoundSample.Generic
                : KeySoundSample.GenericR2;
            try
            {
                return resources.ResolveKeyboardResource(profile, phase, fallback);
            }
            catch (FileNotFoundException)
            {
                return null;
            }
        }
    }
}
