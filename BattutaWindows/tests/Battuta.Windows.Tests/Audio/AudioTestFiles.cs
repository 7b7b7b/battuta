using System.Text;
using Battuta.Core.Audio;

namespace Battuta.Windows.Tests.Audio;

internal static class AudioTestFiles
{
    public static string FindRepositoryRoot()
    {
        foreach (var start in new[] { Directory.GetCurrentDirectory(), AppContext.BaseDirectory })
        {
            var current = new DirectoryInfo(start);
            while (current is not null)
            {
                if (Directory.Exists(Path.Combine(current.FullName, "SimuBoardMac"))
                    && Directory.Exists(Path.Combine(current.FullName, "BattutaWindows")))
                {
                    return current.FullName;
                }

                current = current.Parent;
            }
        }

        throw new DirectoryNotFoundException("Could not locate the Battuta repository root.");
    }

    public static void WriteMonoPcm16Wave(string path, ReadOnlySpan<float> samples, int sampleRate = 48_000)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        const short channelCount = 1;
        const short bitsPerSample = 16;
        const short blockAlign = channelCount * bitsPerSample / 8;
        var dataLength = samples.Length * blockAlign;

        using var stream = File.Create(path);
        using var writer = new BinaryWriter(stream, Encoding.ASCII, leaveOpen: false);
        writer.Write(Encoding.ASCII.GetBytes("RIFF"));
        writer.Write(36 + dataLength);
        writer.Write(Encoding.ASCII.GetBytes("WAVE"));
        writer.Write(Encoding.ASCII.GetBytes("fmt "));
        writer.Write(16);
        writer.Write((short)1);
        writer.Write(channelCount);
        writer.Write(sampleRate);
        writer.Write(sampleRate * blockAlign);
        writer.Write(blockAlign);
        writer.Write(bitsPerSample);
        writer.Write(Encoding.ASCII.GetBytes("data"));
        writer.Write(dataLength);
        foreach (var sample in samples)
        {
            var bounded = Math.Clamp(sample, -1f, 0.9999695f);
            writer.Write((short)Math.Round(bounded * short.MaxValue));
        }
    }

    public static void CreateKeyboardProfile(
        string audioRoot,
        SwitchProfileDefinition profile,
        ReadOnlySpan<float> samples)
    {
        foreach (var phase in Enum.GetValues<KeySoundPhase>())
        {
            foreach (var sample in BuiltInSamplePlan.RequiredSamples(profile, phase))
            {
                WriteMonoPcm16Wave(
                    Path.Combine(
                        audioRoot,
                        profile.Id.Value,
                        phase.DirectoryName(),
                        sample.ResourceName() + ".wav"),
                    samples);
            }
        }
    }

    public static void CreatePointerProfile(
        string audioRoot,
        PointerSoundProfileDefinition profile,
        ReadOnlySpan<float> samples)
    {
        foreach (var phase in new[] { "press", "release" })
        {
            WriteMonoPcm16Wave(
                Path.Combine(audioRoot, "pointer", profile.Id.Value, phase, "PRIMARY.wav"),
                samples);
        }
    }
}
