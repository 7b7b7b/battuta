namespace Battuta.Windows.Audio;

/// <summary>
/// An immutable, onset-aligned, 48 kHz mono floating-point sample ready for realtime playback.
/// </summary>
public sealed class PreparedPcmSample
{
    private readonly float[] samples;

    public PreparedPcmSample(ReadOnlySpan<float> samples)
        : this(samples.ToArray(), takeOwnership: true)
    {
    }

    internal PreparedPcmSample(float[] samples, bool takeOwnership)
    {
        ArgumentNullException.ThrowIfNull(samples);
        if (samples.Length == 0)
        {
            throw new ArgumentException("A prepared audio sample cannot be empty.", nameof(samples));
        }

        for (var index = 0; index < samples.Length; index++)
        {
            if (!float.IsFinite(samples[index]))
            {
                throw new ArgumentException("Prepared audio samples must contain only finite values.", nameof(samples));
            }
        }

        this.samples = takeOwnership ? samples : (float[])samples.Clone();
    }

    public int FrameCount => samples.Length;

    public TimeSpan Duration => TimeSpan.FromSeconds((double)samples.Length / AudioConstants.SampleRate);

    public ReadOnlyMemory<float> Samples => samples;

    internal ReadOnlySpan<float> SampleSpan => samples;
}
