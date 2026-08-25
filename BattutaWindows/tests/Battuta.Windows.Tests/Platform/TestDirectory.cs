using System.IO;

namespace Battuta.Windows.Tests.Platform;

internal sealed class TestDirectory : IDisposable
{
    private readonly string _safeRoot;

    public TestDirectory()
    {
        _safeRoot = System.IO.Path.Combine(
            System.IO.Path.GetTempPath(),
            "Battuta.Windows.Tests");
        Path = System.IO.Path.Combine(_safeRoot, Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(Path);
    }

    public string Path { get; }

    public void Dispose()
    {
        var resolved = System.IO.Path.GetFullPath(Path);
        var prefix = System.IO.Path.GetFullPath(_safeRoot).TrimEnd(
            System.IO.Path.DirectorySeparatorChar,
            System.IO.Path.AltDirectorySeparatorChar) + System.IO.Path.DirectorySeparatorChar;
        if (resolved.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)
            && Directory.Exists(resolved))
        {
            Directory.Delete(resolved, recursive: true);
        }
    }
}
