using Battuta.Windows.Audio;

namespace Battuta.Windows.Tests.Audio;

public sealed class PolyphonicSampleProviderTests
{
    [Fact]
    public void IdleReadReturnsFullStereoSilenceAndKeepsStreamAlive()
    {
        var mixer = new PolyphonicSampleProvider();
        var output = Enumerable.Repeat(1f, 64).ToArray();

        var read = mixer.Read(output);

        Assert.Equal(output.Length, read);
        Assert.All(output, sample => Assert.Equal(0f, sample));
        Assert.Equal(48_000, mixer.WaveFormat.SampleRate);
        Assert.Equal(2, mixer.WaveFormat.Channels);
    }

    [Fact]
    public void GainRateAndMonoToStereoAreAppliedInMemory()
    {
        var mixer = new PolyphonicSampleProvider();
        var sample = new PreparedPcmSample([1f, 0.5f, 0.25f, 0.125f]);
        Assert.True(mixer.TrySchedule(sample, gain: 0.5f, rate: 2f));
        var output = new float[4];

        mixer.Read(output);

        Assert.Equal([0.5f, 0.5f, 0.125f, 0.125f], output);
    }

    [Fact]
    public void SixteenVoicesOverlapAndSeventeenthStealsOldestSlot()
    {
        var mixer = new PolyphonicSampleProvider();
        var quiet = new PreparedPcmSample([0.01f]);
        for (var index = 0; index < AudioConstants.VoiceCount; index++)
        {
            Assert.True(mixer.TrySchedule(quiet, 1, 1));
        }

        var replacement = new PreparedPcmSample([0.2f]);
        Assert.True(mixer.TrySchedule(replacement, 1, 1));
        var output = new float[2];

        mixer.Read(output);

        Assert.Equal(0.35f, output[0], precision: 5);
        Assert.Equal(output[0], output[1]);
        Assert.Equal(1, mixer.VoiceStealCount);
    }

    [Fact]
    public void MixedOutputIsBoundedWhenManyLoudVoicesOverlap()
    {
        var mixer = new PolyphonicSampleProvider();
        var sample = new PreparedPcmSample([0.9f, 0.9f]);
        for (var index = 0; index < AudioConstants.VoiceCount; index++)
        {
            mixer.TrySchedule(sample, 1, 1);
        }

        var output = new float[2];
        mixer.Read(output);

        Assert.Equal([1f, 1f], output);
    }

    [Fact]
    public void RestartResetInvalidatesPendingClicks()
    {
        var mixer = new PolyphonicSampleProvider();
        mixer.TrySchedule(new PreparedPcmSample([0.5f]), 1, 1);

        mixer.ResetForOutputRestart();
        var output = new float[2];
        mixer.Read(output);

        Assert.Equal([0f, 0f], output);
        Assert.Equal(0, mixer.QueuedCommandCount);
    }

    [Fact]
    public void CommandQueueIsBounded()
    {
        var mixer = new PolyphonicSampleProvider();
        var sample = new PreparedPcmSample([0.1f]);
        for (var index = 0; index < AudioConstants.MaximumQueuedCommands; index++)
        {
            Assert.True(mixer.TrySchedule(sample, 1, 1));
        }

        Assert.False(mixer.TrySchedule(sample, 1, 1));
        Assert.Equal(1, mixer.DroppedCommandCount);
        Assert.Equal(AudioConstants.MaximumQueuedCommands, mixer.QueuedCommandCount);
    }

    [Fact]
    public void SchedulingIsSuppressedWhileOutputIsRecovering()
    {
        var mixer = new PolyphonicSampleProvider();
        var sample = new PreparedPcmSample([0.5f]);

        mixer.SuspendForOutputRestart();
        Assert.False(mixer.TrySchedule(sample, 1, 1));
        mixer.ResumeAfterOutputRestart();
        Assert.True(mixer.TrySchedule(sample, 1, 1));
    }

    [Fact]
    public async Task FirstReadCompletesWarmupSignal()
    {
        var mixer = new PolyphonicSampleProvider();
        var wait = mixer.WaitForFirstRenderAsync(TimeSpan.FromSeconds(1));

        mixer.Read(new float[2]);

        await wait;
    }
}
