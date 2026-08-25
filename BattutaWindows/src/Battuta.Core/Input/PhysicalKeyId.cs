namespace Battuta.Core.Input;

/// <summary>
/// A stable, platform-independent physical key identifier.
/// </summary>
/// <remarks>
/// Known identifiers are exposed by <see cref="PhysicalKeys"/>. Platform adapters may
/// create deterministic namespaced identifiers for otherwise unknown scan codes (for
/// example <c>win.scan.e0.001C</c>) so statistics do not collapse distinct keys.
/// Enum ordinals and platform virtual-key values must never be persisted as this value.
/// </remarks>
public readonly record struct PhysicalKeyId
{
    public const int MaximumLength = 128;

    public PhysicalKeyId(string value)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(value);
        if (value.Length > MaximumLength || !value.All(IsAllowedCharacter))
        {
            throw new ArgumentException("Physical key IDs must be safe ASCII identifiers.", nameof(value));
        }

        Value = value;
    }

    public string Value { get; }

    public bool IsValid => !string.IsNullOrEmpty(Value);

    public static bool TryParse(string? value, out PhysicalKeyId keyId)
    {
        if (!string.IsNullOrWhiteSpace(value)
            && value.Length <= MaximumLength
            && value.All(IsAllowedCharacter))
        {
            keyId = new PhysicalKeyId(value);
            return true;
        }

        keyId = default;
        return false;
    }

    public override string ToString() => Value ?? string.Empty;

    private static bool IsAllowedCharacter(char character) =>
        character is >= 'a' and <= 'z'
        or >= 'A' and <= 'Z'
        or >= '0' and <= '9'
        or '.' or '_' or '-';
}
