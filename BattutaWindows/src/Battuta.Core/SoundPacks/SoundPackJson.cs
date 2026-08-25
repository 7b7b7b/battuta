using System.Globalization;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Battuta.Core.SoundPacks;

public sealed class SoundPackAssetIdJsonConverter : JsonConverter<SoundPackAssetId>
{
    public override SoundPackAssetId Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        var value = reader.GetString();
        if (string.IsNullOrWhiteSpace(value))
        {
            throw new JsonException("Sound-pack asset IDs must be non-empty strings.");
        }

        return new SoundPackAssetId(value);
    }

    public override void Write(Utf8JsonWriter writer, SoundPackAssetId value, JsonSerializerOptions options) =>
        writer.WriteStringValue(value.Value);
}

public sealed class SoundPackKeyOverrideJsonConverter : JsonConverter<SoundPackKeyOverride>
{
    public override SoundPackKeyOverride Read(
        ref Utf8JsonReader reader,
        Type typeToConvert,
        JsonSerializerOptions options)
    {
        using var document = JsonDocument.ParseValue(ref reader);
        if (document.RootElement.ValueKind != JsonValueKind.Object
            || !document.RootElement.TryGetProperty("kind", out var kindElement)
            || kindElement.ValueKind != JsonValueKind.String)
        {
            throw new JsonException("A sound-pack key override requires a string kind.");
        }

        return kindElement.GetString() switch
        {
            "inherit" => SoundPackKeyOverride.Inherit,
            "silent" => SoundPackKeyOverride.Silent,
            "asset" => ReadAsset(document.RootElement, options),
            var kind => throw new JsonException($"Unknown sound-pack key override kind: {kind}"),
        };
    }

    public override void Write(
        Utf8JsonWriter writer,
        SoundPackKeyOverride value,
        JsonSerializerOptions options)
    {
        writer.WriteStartObject();
        switch (value.Kind)
        {
            case SoundPackKeyOverrideKind.Inherit:
                writer.WriteString("kind", "inherit");
                break;
            case SoundPackKeyOverrideKind.Silent:
                writer.WriteString("kind", "silent");
                break;
            case SoundPackKeyOverrideKind.Asset when value.AssetId.HasValue:
                writer.WriteString("kind", "asset");
                writer.WriteString("assetID", value.AssetId.Value.Value);
                break;
            default:
                throw new JsonException("An asset override requires an assetID.");
        }
        writer.WriteEndObject();
    }

    private static SoundPackKeyOverride ReadAsset(JsonElement root, JsonSerializerOptions options)
    {
        if (!root.TryGetProperty("assetID", out var assetElement)
            || assetElement.ValueKind != JsonValueKind.String)
        {
            throw new JsonException("An asset override requires an assetID.");
        }

        var value = assetElement.Deserialize<SoundPackAssetId>(options);
        return SoundPackKeyOverride.Asset(value);
    }
}

internal sealed class SoundPackDateTimeOffsetJsonConverter : JsonConverter<DateTimeOffset>
{
    private const string OutputFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'";

    public override DateTimeOffset Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        var value = reader.GetString();
        if (value is null
            || !DateTimeOffset.TryParse(
                value,
                CultureInfo.InvariantCulture,
                DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal,
                out var date))
        {
            throw new JsonException("Invalid ISO-8601 sound-pack date.");
        }

        return date;
    }

    public override void Write(Utf8JsonWriter writer, DateTimeOffset value, JsonSerializerOptions options) =>
        writer.WriteStringValue(value.UtcDateTime.ToString(OutputFormat, CultureInfo.InvariantCulture));
}

public static class SoundPackManifestJson
{
    private static readonly JsonSerializerOptions Options = CreateOptions();

    public static byte[] Encode(SoundPackManifest manifest) =>
        JsonSerializer.SerializeToUtf8Bytes(manifest, Options);

    public static string EncodeToString(SoundPackManifest manifest) =>
        Encoding.UTF8.GetString(Encode(manifest));

    public static SoundPackManifest Decode(
        ReadOnlySpan<byte> data,
        SoundPackValidationLimits? limits = null)
    {
        limits ??= SoundPackValidationLimits.Standard;
        if (data.Length > limits.MaximumManifestBytes)
        {
            throw new SoundPackException(
                SoundPackErrorKind.SizeLimitExceeded,
                "manifest.json is too large.");
        }

        try
        {
            return JsonSerializer.Deserialize<SoundPackManifest>(data, Options)
                ?? throw new JsonException("The manifest is empty.");
        }
        catch (SoundPackException)
        {
            throw;
        }
        catch (Exception exception) when (exception is JsonException or NotSupportedException or ArgumentException)
        {
            throw new SoundPackException(
                SoundPackErrorKind.InvalidManifest,
                $"Invalid sound-pack manifest: {exception.Message}",
                exception);
        }
    }

    private static JsonSerializerOptions CreateOptions()
    {
        var options = new JsonSerializerOptions
        {
            WriteIndented = true,
            Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
            PropertyNameCaseInsensitive = false,
            RespectNullableAnnotations = true,
            DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        };
        options.Converters.Add(new SoundPackDateTimeOffsetJsonConverter());
        return options;
    }
}
