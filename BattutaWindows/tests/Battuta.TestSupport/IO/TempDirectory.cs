using System.Runtime.InteropServices;

namespace Battuta.TestSupport.IO;

/// <summary>
/// Owns an isolated temporary directory and removes it without following
/// reparse points when disposed.
/// </summary>
public sealed class TempDirectory : IDisposable, IAsyncDisposable
{
    private const int CleanupAttempts = 4;
    private readonly object gate = new();
    private bool disposed;

    public TempDirectory(string prefix = "battuta-test")
        : this(System.IO.Path.GetTempPath(), prefix)
    {
    }

    public TempDirectory(string parentDirectory, string prefix)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(parentDirectory);
        ValidatePrefix(prefix);

        var parent = System.IO.Path.GetFullPath(parentDirectory);
        Directory.CreateDirectory(parent);

        Path = System.IO.Path.Combine(parent, $"{prefix}-{Guid.NewGuid():N}");
        Directory.CreateDirectory(Path);
    }

    /// <summary>The absolute path owned by this instance.</summary>
    public string Path { get; }

    /// <summary>
    /// Resolves a relative path and rejects paths that leave this temporary root.
    /// </summary>
    public string GetPath(string relativePath)
    {
        ThrowIfDisposed();
        ArgumentNullException.ThrowIfNull(relativePath);

        if (System.IO.Path.IsPathRooted(relativePath))
        {
            throw new ArgumentException("The path must be relative to the test directory.", nameof(relativePath));
        }

        var root = System.IO.Path.GetFullPath(Path);
        var candidate = System.IO.Path.GetFullPath(System.IO.Path.Combine(root, relativePath));
        if (!IsWithinRoot(candidate, root))
        {
            throw new ArgumentException("The path leaves the test directory.", nameof(relativePath));
        }

        return candidate;
    }

    public string CreateSubdirectory(string relativePath)
    {
        var path = GetPath(relativePath);
        Directory.CreateDirectory(path);
        return path;
    }

    public string WriteAllText(string relativePath, string contents)
    {
        ArgumentNullException.ThrowIfNull(contents);
        var path = PrepareFilePath(relativePath);
        File.WriteAllText(path, contents, new System.Text.UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
        return path;
    }

    public string WriteAllBytes(string relativePath, ReadOnlySpan<byte> contents)
    {
        var path = PrepareFilePath(relativePath);
        File.WriteAllBytes(path, contents);
        return path;
    }

    public ValueTask DisposeAsync()
    {
        Dispose();
        return ValueTask.CompletedTask;
    }

    public void Dispose()
    {
        lock (gate)
        {
            if (disposed)
            {
                return;
            }

            DeleteWithRetries(Path);
            Volatile.Write(ref disposed, true);
        }

        GC.SuppressFinalize(this);
    }

    private string PrepareFilePath(string relativePath)
    {
        var path = GetPath(relativePath);
        var parent = System.IO.Path.GetDirectoryName(path);
        if (!string.IsNullOrEmpty(parent))
        {
            Directory.CreateDirectory(parent);
        }

        return path;
    }

    private void ThrowIfDisposed()
    {
        ObjectDisposedException.ThrowIf(Volatile.Read(ref disposed), this);
    }

    private static bool IsWithinRoot(string candidate, string root)
    {
        if (string.Equals(candidate, root, PathComparison))
        {
            return true;
        }

        var rootWithSeparator = root.EndsWith(System.IO.Path.DirectorySeparatorChar)
            ? root
            : root + System.IO.Path.DirectorySeparatorChar;
        return candidate.StartsWith(rootWithSeparator, PathComparison);
    }

    private static StringComparison PathComparison => RuntimeInformation.IsOSPlatform(OSPlatform.Windows)
        ? StringComparison.OrdinalIgnoreCase
        : StringComparison.Ordinal;

    private static void ValidatePrefix(string prefix)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(prefix);
        if (prefix.Length > 48 || prefix.Any(character => !IsSafePrefixCharacter(character)))
        {
            throw new ArgumentException(
                "The prefix may contain only ASCII letters, digits, periods, underscores, and hyphens.",
                nameof(prefix));
        }
    }

    private static bool IsSafePrefixCharacter(char character) =>
        character is >= 'a' and <= 'z'
        or >= 'A' and <= 'Z'
        or >= '0' and <= '9'
        or '.' or '_' or '-';

    private static void DeleteWithRetries(string directoryPath)
    {
        Exception? lastError = null;
        for (var attempt = 0; attempt < CleanupAttempts; attempt++)
        {
            try
            {
                SafeDeleteDirectory(directoryPath);
                return;
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException)
            {
                lastError = error;
                if (attempt + 1 < CleanupAttempts)
                {
                    Thread.Sleep(TimeSpan.FromMilliseconds(20 * (attempt + 1)));
                }
            }
        }

        throw new IOException($"Could not remove test directory '{directoryPath}'.", lastError);
    }

    private static void SafeDeleteDirectory(string directoryPath)
    {
        if (!Directory.Exists(directoryPath))
        {
            return;
        }

        var root = System.IO.Path.GetFullPath(directoryPath);
        foreach (var entry in Directory.EnumerateFileSystemEntries(root))
        {
            var fullPath = System.IO.Path.GetFullPath(entry);
            if (!IsWithinRoot(fullPath, root))
            {
                throw new IOException($"Refusing to delete a path outside the test directory: '{fullPath}'.");
            }

            var attributes = File.GetAttributes(fullPath);
            if ((attributes & FileAttributes.ReparsePoint) != 0)
            {
                DeleteReparsePoint(fullPath, attributes);
            }
            else if ((attributes & FileAttributes.Directory) != 0)
            {
                SafeDeleteDirectory(fullPath);
            }
            else
            {
                File.SetAttributes(fullPath, FileAttributes.Normal);
                File.Delete(fullPath);
            }
        }

        File.SetAttributes(root, FileAttributes.Directory);
        Directory.Delete(root, recursive: false);
    }

    private static void DeleteReparsePoint(string path, FileAttributes attributes)
    {
        if ((attributes & FileAttributes.Directory) != 0)
        {
            Directory.Delete(path, recursive: false);
            return;
        }

        File.SetAttributes(path, FileAttributes.Normal);
        File.Delete(path);
    }
}
