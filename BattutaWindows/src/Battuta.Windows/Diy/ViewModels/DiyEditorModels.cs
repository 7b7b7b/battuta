using Battuta.Core.Audio;
using Battuta.Core.Input;
using Battuta.Core.SoundPacks;
using Battuta.Windows.Diy.Audio;

namespace Battuta.Windows.Diy.ViewModels;

public enum DiyEditorMappingMode
{
    Generic,
    Recommended,
    PerKey,
}

public enum DiyEditorSlotKind
{
    Generic,
    Row,
    Special,
    Key,
}

public sealed record DiyEditorSlot
{
    private DiyEditorSlot(
        DiyEditorSlotKind kind,
        KeyboardRowId? row,
        KeyboardSpecialKeyId? special,
        PhysicalKeyId? key)
    {
        Kind = kind;
        Row = row;
        Special = special;
        Key = key;
    }

    public DiyEditorSlotKind Kind { get; }
    public KeyboardRowId? Row { get; }
    public KeyboardSpecialKeyId? Special { get; }
    public PhysicalKeyId? Key { get; }

    public static DiyEditorSlot Generic { get; } = new(DiyEditorSlotKind.Generic, null, null, null);
    public static DiyEditorSlot ForRow(KeyboardRowId row) => new(DiyEditorSlotKind.Row, row, null, null);
    public static DiyEditorSlot ForSpecial(KeyboardSpecialKeyId special) =>
        new(DiyEditorSlotKind.Special, null, special, null);
    public static DiyEditorSlot ForKey(PhysicalKeyId key) => new(DiyEditorSlotKind.Key, null, null, key);

    public string DisplayName => Kind switch
    {
        DiyEditorSlotKind.Generic => "所有按键",
        DiyEditorSlotKind.Row when Row is { } row => row switch
        {
            KeyboardRowId.R0 => "R1 · 数字行",
            KeyboardRowId.R1 => "R2 · Q 行",
            KeyboardRowId.R2 => "R3 · A 行",
            KeyboardRowId.R3 => "R4 · Z 行",
            KeyboardRowId.R4 => "功能 / 其他键",
            _ => row.ToString(),
        },
        DiyEditorSlotKind.Special when Special is { } special => special switch
        {
            KeyboardSpecialKeyId.Space => "空格",
            KeyboardSpecialKeyId.Enter => "回车",
            KeyboardSpecialKeyId.Backspace => "退格",
            _ => special.ToString(),
        },
        DiyEditorSlotKind.Key when Key is { } key && PhysicalKeyCatalog.TryGet(key, out var definition) =>
            WindowsKeyLabel(definition),
        DiyEditorSlotKind.Key when Key is { } key => key.Value,
        _ => string.Empty,
    };

    private static string WindowsKeyLabel(KeyboardKeyDefinition definition) =>
        WindowsKeyDisplayCatalog.LabelFor(definition.Id);
}

public sealed record DiyEditorAudioTarget(DiyEditorSlot Slot, KeySoundPhase Phase);

public enum DiyKeyOverrideChoice
{
    Inherit,
    Silent,
    Asset,
}

public sealed record DiyEditorError(string Title, string Message);

public sealed record DiySplitDraft(
    Guid Id,
    DiyEditorSlot Target,
    AudioSplitAnalysis Analysis);

public interface IDiyAudioPreviewService
{
    Task PreviewAsync(string audioPath, CancellationToken cancellationToken = default);
}

public interface IDiyBuiltInAudioLocator
{
    string? FindAudio(string profileId, PhysicalKeyId key, KeySoundPhase phase);
}

public sealed class NullDiyAudioPreviewService : IDiyAudioPreviewService
{
    public Task PreviewAsync(string audioPath, CancellationToken cancellationToken = default) =>
        Task.CompletedTask;
}

public sealed class NullDiyBuiltInAudioLocator : IDiyBuiltInAudioLocator
{
    public string? FindAudio(string profileId, PhysicalKeyId key, KeySoundPhase phase) => null;
}
