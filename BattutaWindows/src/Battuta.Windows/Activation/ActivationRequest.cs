using System.Text.Json.Serialization;
using System.IO;

namespace Battuta.Windows.Activation;

[JsonConverter(typeof(JsonStringEnumConverter<ActivationKind>))]
public enum ActivationKind
{
    Start,
    Startup,
    ShowTray,
    ShowStatistics,
    ShowDiyEditor,
    OpenSoundPack,
}

public sealed record ActivationRequest(
    ActivationKind Kind,
    IReadOnlyList<string> Arguments,
    string? WorkingDirectory = null,
    string? FilePath = null)
{
    public static ActivationRequest FromArguments(
        IEnumerable<string> arguments,
        string? workingDirectory = null)
    {
        ArgumentNullException.ThrowIfNull(arguments);
        var values = arguments.ToArray();
        if (values.Contains("--startup", StringComparer.OrdinalIgnoreCase))
        {
            return new ActivationRequest(ActivationKind.Startup, values, workingDirectory);
        }

        if (values.Contains("--show-stats", StringComparer.OrdinalIgnoreCase))
        {
            return new ActivationRequest(ActivationKind.ShowStatistics, values, workingDirectory);
        }

        if (values.Contains("--show-diy", StringComparer.OrdinalIgnoreCase))
        {
            return new ActivationRequest(ActivationKind.ShowDiyEditor, values, workingDirectory);
        }

        var soundPackIndex = Array.FindIndex(
            values,
            value => string.Equals(value, "--open-sound-pack", StringComparison.OrdinalIgnoreCase));
        if (soundPackIndex >= 0 && soundPackIndex + 1 < values.Length)
        {
            var filePath = ResolvePath(values[soundPackIndex + 1], workingDirectory);
            return new ActivationRequest(
                ActivationKind.OpenSoundPack,
                values,
                workingDirectory,
                filePath);
        }

        return new ActivationRequest(ActivationKind.Start, values, workingDirectory);
    }

    private static string ResolvePath(string path, string? workingDirectory)
    {
        if (Path.IsPathFullyQualified(path))
        {
            return Path.GetFullPath(path);
        }

        var root = string.IsNullOrWhiteSpace(workingDirectory)
            ? Environment.CurrentDirectory
            : workingDirectory;
        return Path.GetFullPath(path, root);
    }
}
