using System.Globalization;
using System.Diagnostics.CodeAnalysis;
using System.Text;
using Battuta.Core.Audio;
using Battuta.Core.Input;

namespace Battuta.Core.SoundPacks;

public sealed record SoundPackValidationLimits
{
    public long MaximumManifestBytes { get; init; } = 1_048_576;
    public long MaximumPackBytes { get; init; } = 134_217_728;
    public long MaximumAssetBytes { get; init; } = 25_165_824;
    public int MaximumAssetCount { get; init; } = 256;
    public int MaximumFileCount { get; init; } = 512;
    public double MaximumAudioDurationSeconds { get; init; } = 5;
    public double MaximumTotalAudioDurationSeconds { get; init; } = 180;
    public double MinimumAudioDurationSeconds { get; init; } = 0.005;
    public int MaximumTextLength { get; init; } = 8_192;

    public static SoundPackValidationLimits Standard { get; } = new();
}

public enum SoundPackErrorKind
{
    InvalidManifest,
    UnsupportedSchema,
    UnsafePath,
    UnsafeFile,
    MissingAsset,
    InvalidAudio,
    SizeLimitExceeded,
    HashMismatch,
    PackAlreadyExists,
    PackNotFound,
    FileOperation,
}

public sealed class SoundPackException : Exception
{
    public SoundPackException(SoundPackErrorKind kind, string message, Exception? innerException = null)
        : base(message, innerException)
    {
        Kind = kind;
    }

    public SoundPackErrorKind Kind { get; }
}

public static class SoundPackValidator
{
    private static readonly HashSet<string> AllowedRows =
        Enum.GetValues<KeyboardRowId>()
            .Select(SoundPackV1WireNames.Row)
            .ToHashSet(StringComparer.Ordinal);

    private static readonly HashSet<string> AllowedSpecials =
        Enum.GetValues<KeyboardSpecialKeyId>()
            .Select(SoundPackV1WireNames.Special)
            .ToHashSet(StringComparer.Ordinal);

    public static void Validate(
        SoundPackManifest manifest,
        SoundPackValidationLimits? limits = null)
    {
        ArgumentNullException.ThrowIfNull(manifest);
        limits ??= SoundPackValidationLimits.Standard;

        if (manifest.SchemaVersion != SoundPackManifest.CurrentSchemaVersion)
        {
            Throw(SoundPackErrorKind.UnsupportedSchema,
                $"Unsupported sound-pack schema version {manifest.SchemaVersion}.");
        }

        ValidateRequiredText(manifest.Name, "name", 128);
        ValidateRequiredText(manifest.LayoutId, "layoutID", 128);
        if (!string.Equals(manifest.LayoutId, KeyboardLayoutCatalog.DefaultLayoutId, StringComparison.Ordinal))
        {
            Throw(SoundPackErrorKind.InvalidManifest,
                $"Unsupported keyboard layout: {manifest.LayoutId}");
        }

        ValidateOptionalText(manifest.Author, "author", limits);
        ValidateOptionalText(manifest.Family, "family", limits);
        ValidateOptionalText(manifest.Tone, "tone", limits);
        ValidateOptionalText(manifest.Notes, "notes", limits);
        ValidateOptionalText(manifest.BaseProfileId, "baseProfileID", limits);
        if (manifest.BaseProfileId is not null
            && !SwitchProfileCatalog.TryGet(manifest.BaseProfileId, out _))
        {
            Throw(SoundPackErrorKind.InvalidManifest,
                $"Unknown built-in baseProfileID: {manifest.BaseProfileId}");
        }

        if (manifest.Assets is null || manifest.Press is null || manifest.Release is null
            || manifest.Attributions is null)
        {
            Throw(SoundPackErrorKind.InvalidManifest, "Required manifest collections are missing.");
        }

        if (manifest.Assets.Count > limits.MaximumAssetCount)
        {
            Throw(SoundPackErrorKind.SizeLimitExceeded,
                $"Audio asset count exceeds {limits.MaximumAssetCount}.");
        }

        ValidateAssignments(manifest.Press, manifest, "press");
        ValidateAssignments(manifest.Release, manifest, "release");

        var paths = new HashSet<string>(StringComparer.Ordinal);
        var totalDuration = 0d;
        foreach (var (dictionaryId, asset) in manifest.Assets)
        {
            if (asset is null)
            {
                Throw(SoundPackErrorKind.InvalidManifest, "An audio asset entry is null.");
            }

            if (!string.Equals(dictionaryId, asset.Id.Value, StringComparison.Ordinal))
            {
                Throw(SoundPackErrorKind.InvalidManifest,
                    "The assets dictionary key does not match its resource ID.");
            }

            if (!string.Equals(asset.Id.Value, asset.Sha256, StringComparison.Ordinal)
                || !IsLowercaseSha256(asset.Sha256))
            {
                Throw(SoundPackErrorKind.InvalidManifest,
                    "Resource IDs must equal a lowercase SHA-256 digest.");
            }

            var expectedPath = $"assets/{asset.Sha256}.wav";
            if (!string.Equals(asset.RelativePath, expectedPath, StringComparison.Ordinal))
            {
                Throw(SoundPackErrorKind.UnsafePath, $"Unsafe resource path: {asset.RelativePath}");
            }
            SoundPackPathValidator.ValidateRelativePath(asset.RelativePath);
            if (!paths.Add(asset.RelativePath))
            {
                Throw(SoundPackErrorKind.InvalidManifest, "Multiple resources use the same path.");
            }

            if (!double.IsFinite(asset.DurationSeconds)
                || asset.DurationSeconds < limits.MinimumAudioDurationSeconds
                || asset.DurationSeconds > limits.MaximumAudioDurationSeconds)
            {
                Throw(SoundPackErrorKind.InvalidAudio,
                    $"Audio duration is out of range: {asset.RelativePath}");
            }
            totalDuration += asset.DurationSeconds;

            if (asset.SampleRate != 48_000 || asset.ChannelCount != 1)
            {
                Throw(SoundPackErrorKind.InvalidAudio,
                    $"Audio must be 48 kHz mono: {asset.RelativePath}");
            }

            if (asset.ByteCount <= 0 || asset.ByteCount > limits.MaximumAssetBytes)
            {
                Throw(SoundPackErrorKind.SizeLimitExceeded,
                    $"Audio resource is too large: {asset.RelativePath}");
            }

            ValidateOptionalText(asset.OriginalFilename, "originalFilename", limits);
            if (asset.License is not null)
            {
                ValidateRequiredText(asset.License.Name, "license.name", 256);
                ValidateOptionalText(asset.License.SourceUrl, "license.sourceURL", limits);
                ValidateOptionalText(asset.License.Author, "license.author", limits);
                ValidateOptionalText(asset.License.Notice, "license.notice", limits);
            }
        }

        if (!double.IsFinite(totalDuration)
            || totalDuration > limits.MaximumTotalAudioDurationSeconds)
        {
            Throw(SoundPackErrorKind.SizeLimitExceeded,
                $"Total audio duration exceeds {limits.MaximumTotalAudioDurationSeconds} seconds.");
        }

        if (manifest.Attributions.Count > limits.MaximumAssetCount)
        {
            Throw(SoundPackErrorKind.SizeLimitExceeded, "There are too many attribution entries.");
        }
        foreach (var attribution in manifest.Attributions)
        {
            if (attribution is null)
            {
                Throw(SoundPackErrorKind.InvalidManifest, "An attribution entry is null.");
            }
            ValidateRequiredText(attribution.Title, "attribution.title", 512);
            ValidateOptionalText(attribution.Author, "attribution.author", limits);
            ValidateOptionalText(attribution.SourceUrl, "attribution.sourceURL", limits);
            ValidateOptionalText(attribution.LicenseName, "attribution.licenseName", limits);
            ValidateOptionalText(attribution.Notice, "attribution.notice", limits);
        }
    }

    private static void ValidateAssignments(
        SoundPackPhaseAssignments assignments,
        SoundPackManifest manifest,
        string phase)
    {
        if (assignments.Rows is null || assignments.Specials is null || assignments.KeyOverrides is null)
        {
            Throw(SoundPackErrorKind.InvalidManifest, $"{phase} assignments are incomplete.");
        }

        var unknownRows = assignments.Rows.Keys.Where(key => !AllowedRows.Contains(key)).ToArray();
        if (unknownRows.Length > 0)
        {
            Throw(SoundPackErrorKind.InvalidManifest,
                $"{phase} contains unknown rows: {string.Join(", ", unknownRows)}");
        }

        var unknownSpecials = assignments.Specials.Keys
            .Where(key => !AllowedSpecials.Contains(key)).ToArray();
        if (unknownSpecials.Length > 0)
        {
            Throw(SoundPackErrorKind.InvalidManifest,
                $"{phase} contains unknown special keys: {string.Join(", ", unknownSpecials)}");
        }

        foreach (var key in assignments.KeyOverrides.Keys)
        {
            if (!IsSafeIdentifier(key))
            {
                Throw(SoundPackErrorKind.InvalidManifest,
                    $"{phase} contains an invalid key ID: {key}");
            }
        }

        foreach (var assetId in assignments.ReferencedAssetIds())
        {
            if (!manifest.Assets.ContainsKey(assetId.Value))
            {
                Throw(SoundPackErrorKind.MissingAsset,
                    $"The sound pack is missing audio asset {assetId.Value}.");
            }
        }
    }

    private static void ValidateRequiredText(string? value, string field, int maximum)
    {
        if (string.IsNullOrWhiteSpace(value) || TextElementCount(value) > maximum)
        {
            Throw(SoundPackErrorKind.InvalidManifest, $"{field} is empty or too long.");
        }
    }

    private static void ValidateOptionalText(
        string? value,
        string field,
        SoundPackValidationLimits limits)
    {
        if (value is not null && TextElementCount(value) > limits.MaximumTextLength)
        {
            Throw(SoundPackErrorKind.InvalidManifest, $"{field} is too long.");
        }
    }

    private static int TextElementCount(string value) =>
        new StringInfo(value).LengthInTextElements;

    private static bool IsSafeIdentifier(string value)
    {
        if (string.IsNullOrEmpty(value) || TextElementCount(value) > 128)
        {
            return false;
        }

        return value.EnumerateRunes().All(rune =>
            Rune.IsLetterOrDigit(rune)
            || rune.Value is '.' or '_' or '-');
    }

    private static bool IsLowercaseSha256(string value) =>
        value.Length == 64
        && value.All(character => character is >= '0' and <= '9' or >= 'a' and <= 'f');

    [DoesNotReturn]
    private static void Throw(SoundPackErrorKind kind, string message) =>
        throw new SoundPackException(kind, message);
}

public static class SoundPackPathValidator
{
    public static void ValidateRelativePath(string path)
    {
        if (string.IsNullOrEmpty(path)
            || Encoding.UTF8.GetByteCount(path) > 1_024
            || path[0] == '/'
            || path.Contains('\\')
            || path.Contains('\0'))
        {
            throw new SoundPackException(SoundPackErrorKind.UnsafePath,
                $"Unsafe sound-pack path: {path}");
        }

        var components = path.Split('/', StringSplitOptions.None);
        if (components.Length is 0 or > 16
            || components.Any(component =>
                component.Length == 0
                || component is "." or ".."
                || Encoding.UTF8.GetByteCount(component) > 255))
        {
            throw new SoundPackException(SoundPackErrorKind.UnsafePath,
                $"Unsafe sound-pack path: {path}");
        }
    }
}
