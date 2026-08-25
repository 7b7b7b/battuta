using System.Globalization;

namespace Battuta.Windows.Updates;

public readonly struct SemanticVersion : IComparable<SemanticVersion>, IEquatable<SemanticVersion>
{
    private readonly PrereleaseIdentifier[] _prerelease;
    private readonly string[] _buildMetadata;

    public SemanticVersion(
        int major,
        int minor,
        int patch,
        IEnumerable<PrereleaseIdentifier>? prerelease = null,
        IEnumerable<string>? buildMetadata = null)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(major);
        ArgumentOutOfRangeException.ThrowIfNegative(minor);
        ArgumentOutOfRangeException.ThrowIfNegative(patch);
        Major = major;
        Minor = minor;
        Patch = patch;
        _prerelease = prerelease?.ToArray() ?? [];
        _buildMetadata = buildMetadata?.ToArray() ?? [];
    }

    public int Major { get; }

    public int Minor { get; }

    public int Patch { get; }

    public IReadOnlyList<PrereleaseIdentifier> Prerelease => _prerelease ?? [];

    public IReadOnlyList<string> BuildMetadata => _buildMetadata ?? [];

    public static bool TryParse(string? tagOrVersion, out SemanticVersion version)
    {
        version = default;
        if (string.IsNullOrWhiteSpace(tagOrVersion))
        {
            return false;
        }

        var value = tagOrVersion.Trim();
        if (value.StartsWith('v'))
        {
            value = value[1..];
        }

        var buildSplit = value.Split('+');
        if (buildSplit.Length > 2)
        {
            return false;
        }

        var versionSplit = buildSplit[0].Split('-', 2);
        var core = versionSplit[0].Split('.');
        if (core.Length != 3
            || !TryParseCoreNumber(core[0], out var major)
            || !TryParseCoreNumber(core[1], out var minor)
            || !TryParseCoreNumber(core[2], out var patch))
        {
            return false;
        }

        var prerelease = new List<PrereleaseIdentifier>();
        if (versionSplit.Length == 2)
        {
            var identifiers = versionSplit[1].Split('.');
            if (identifiers.Length == 0)
            {
                return false;
            }

            foreach (var identifier in identifiers)
            {
                if (!IsValidIdentifier(identifier))
                {
                    return false;
                }

                if (IsAsciiInteger(identifier))
                {
                    if ((identifier.Length > 1 && identifier[0] == '0')
                        || !int.TryParse(identifier, out var number))
                    {
                        return false;
                    }

                    prerelease.Add(PrereleaseIdentifier.Numeric(number));
                }
                else
                {
                    prerelease.Add(PrereleaseIdentifier.AlphaNumeric(identifier));
                }
            }
        }

        var metadata = Array.Empty<string>();
        if (buildSplit.Length == 2)
        {
            metadata = buildSplit[1].Split('.');
            if (metadata.Length == 0 || metadata.Any(identifier => !IsValidIdentifier(identifier)))
            {
                return false;
            }
        }

        version = new SemanticVersion(major, minor, patch, prerelease, metadata);
        return true;
    }

    public static SemanticVersion Parse(string tagOrVersion)
    {
        return TryParse(tagOrVersion, out var value)
            ? value
            : throw new FormatException($"Invalid semantic version: {tagOrVersion}");
    }

    public int CompareTo(SemanticVersion other)
    {
        var result = Major.CompareTo(other.Major);
        if (result != 0) return result;
        result = Minor.CompareTo(other.Minor);
        if (result != 0) return result;
        result = Patch.CompareTo(other.Patch);
        if (result != 0) return result;

        if (Prerelease.Count == 0 && other.Prerelease.Count != 0) return 1;
        if (Prerelease.Count != 0 && other.Prerelease.Count == 0) return -1;

        for (var index = 0; index < Math.Min(Prerelease.Count, other.Prerelease.Count); index++)
        {
            result = Prerelease[index].CompareTo(other.Prerelease[index]);
            if (result != 0) return result;
        }

        return Prerelease.Count.CompareTo(other.Prerelease.Count);
    }

    public bool Equals(SemanticVersion other) => CompareTo(other) == 0;

    public override bool Equals(object? obj) => obj is SemanticVersion other && Equals(other);

    public override int GetHashCode()
    {
        var hash = new HashCode();
        hash.Add(Major);
        hash.Add(Minor);
        hash.Add(Patch);
        foreach (var identifier in Prerelease)
        {
            hash.Add(identifier);
        }

        return hash.ToHashCode();
    }

    public override string ToString()
    {
        var value = $"{Major}.{Minor}.{Patch}";
        if (Prerelease.Count > 0)
        {
            value += "-" + string.Join('.', Prerelease);
        }

        if (BuildMetadata.Count > 0)
        {
            value += "+" + string.Join('.', BuildMetadata);
        }

        return value;
    }

    public static bool operator <(SemanticVersion left, SemanticVersion right) => left.CompareTo(right) < 0;
    public static bool operator >(SemanticVersion left, SemanticVersion right) => left.CompareTo(right) > 0;
    public static bool operator <=(SemanticVersion left, SemanticVersion right) => left.CompareTo(right) <= 0;
    public static bool operator >=(SemanticVersion left, SemanticVersion right) => left.CompareTo(right) >= 0;
    public static bool operator ==(SemanticVersion left, SemanticVersion right) => left.Equals(right);
    public static bool operator !=(SemanticVersion left, SemanticVersion right) => !left.Equals(right);

    private static bool TryParseCoreNumber(string text, out int number)
    {
        number = 0;
        return IsAsciiInteger(text)
            && (text == "0" || text[0] != '0')
            && int.TryParse(text, out number);
    }

    private static bool IsAsciiInteger(string value) =>
        value.Length > 0 && value.All(character => character is >= '0' and <= '9');

    private static bool IsValidIdentifier(string value) =>
        value.Length > 0 && value.All(character =>
            character is >= '0' and <= '9'
                or >= 'A' and <= 'Z'
                or >= 'a' and <= 'z'
                or '-');
}

public readonly record struct PrereleaseIdentifier : IComparable<PrereleaseIdentifier>
{
    private PrereleaseIdentifier(int? numericValue, string text)
    {
        NumericValue = numericValue;
        Text = text;
    }

    public int? NumericValue { get; }

    public string Text { get; }

    public static PrereleaseIdentifier Numeric(int value)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(value);
        return new PrereleaseIdentifier(value, value.ToString(CultureInfo.InvariantCulture));
    }

    public static PrereleaseIdentifier AlphaNumeric(string value)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(value);
        return new PrereleaseIdentifier(null, value);
    }

    public int CompareTo(PrereleaseIdentifier other)
    {
        if (NumericValue.HasValue && other.NumericValue.HasValue)
        {
            return NumericValue.Value.CompareTo(other.NumericValue.Value);
        }

        if (NumericValue.HasValue) return -1;
        if (other.NumericValue.HasValue) return 1;
        return string.Compare(Text, other.Text, StringComparison.Ordinal);
    }

    public override string ToString() => Text;

    public static bool operator <(PrereleaseIdentifier left, PrereleaseIdentifier right) =>
        left.CompareTo(right) < 0;

    public static bool operator >(PrereleaseIdentifier left, PrereleaseIdentifier right) =>
        left.CompareTo(right) > 0;

    public static bool operator <=(PrereleaseIdentifier left, PrereleaseIdentifier right) =>
        left.CompareTo(right) <= 0;

    public static bool operator >=(PrereleaseIdentifier left, PrereleaseIdentifier right) =>
        left.CompareTo(right) >= 0;
}
