using System.Buffers;
using System.IO;
using System.Text;
using Battuta.Core.SoundPacks;

namespace Battuta.Windows.Diy.Packages;

internal static class DiySoundPackFileSafety
{
    private static readonly SearchValues<char> WindowsInvalidComponentCharacters =
        SearchValues.Create("<>:\"\\|?*");

    private static readonly HashSet<string> WindowsReservedNames = new(
        new[]
        {
            "CON", "PRN", "AUX", "NUL", "CLOCK$",
            "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
            "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
        },
        StringComparer.OrdinalIgnoreCase);

    public static string CanonicalPath(string path)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        return Path.TrimEndingDirectorySeparator(Path.GetFullPath(path));
    }

    public static void ValidatePackageRoot(string path, bool mustExist = true)
    {
        var root = CanonicalPath(path);
        if (!root.EndsWith(".simuboardpack", StringComparison.OrdinalIgnoreCase))
        {
            Throw(SoundPackErrorKind.InvalidManifest, "Package extension must be .simuboardpack.");
        }

        if (!mustExist)
        {
            return;
        }

        if (!Directory.Exists(root))
        {
            Throw(SoundPackErrorKind.UnsafeFile, "The sound-pack package is not a directory.");
        }

        RejectReparsePoint(root);
    }

    public static void ValidateLogicalRelativePath(string logicalPath)
    {
        SoundPackPathValidator.ValidateRelativePath(logicalPath);
        foreach (var component in logicalPath.Split('/'))
        {
            if (component.AsSpan().IndexOfAny(WindowsInvalidComponentCharacters) >= 0 ||
                component.Any(character => char.IsControl(character)) ||
                component.EndsWith(' ') ||
                component.EndsWith('.') ||
                WindowsReservedNames.Contains(component.Split('.')[0]))
            {
                Throw(SoundPackErrorKind.UnsafePath, $"Unsafe Windows package path: {logicalPath}");
            }

            if (Encoding.UTF8.GetByteCount(component) > 255)
            {
                Throw(SoundPackErrorKind.UnsafePath, $"Package path component is too long: {logicalPath}");
            }
        }
    }

    public static string DescendantPath(string rootPath, string logicalRelativePath)
    {
        ValidateLogicalRelativePath(logicalRelativePath);
        var root = CanonicalPath(rootPath);
        var relativeNative = logicalRelativePath.Replace('/', Path.DirectorySeparatorChar);
        var candidate = Path.GetFullPath(Path.Combine(root, relativeNative));
        var prefix = root + Path.DirectorySeparatorChar;
        if (!candidate.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
        {
            Throw(SoundPackErrorKind.UnsafePath, $"Path leaves the package root: {logicalRelativePath}");
        }

        return candidate;
    }

    public static string RelativeLogicalPath(string rootPath, string entryPath)
    {
        var root = CanonicalPath(rootPath);
        var entry = Path.GetFullPath(entryPath);
        var native = Path.GetRelativePath(root, entry);
        if (native == "." || Path.IsPathRooted(native) ||
            native == ".." || native.StartsWith($"..{Path.DirectorySeparatorChar}", StringComparison.Ordinal))
        {
            Throw(SoundPackErrorKind.UnsafePath, $"Path leaves the package root: {entryPath}");
        }

        var logical = native.Replace(Path.DirectorySeparatorChar, '/');
        ValidateLogicalRelativePath(logical);
        return logical;
    }

    public static long ValidateRegularFile(string path, long maximumBytes)
    {
        var fullPath = Path.GetFullPath(path);
        var file = new FileInfo(fullPath);
        if (!file.Exists)
        {
            Throw(SoundPackErrorKind.UnsafeFile, $"Missing regular file: {fullPath}");
        }

        var attributes = file.Attributes;
        if ((attributes & (FileAttributes.Directory | FileAttributes.ReparsePoint | FileAttributes.Device)) != 0)
        {
            Throw(SoundPackErrorKind.UnsafeFile, $"Unsafe package file: {fullPath}");
        }

        if (file.Length < 0 || file.Length > maximumBytes)
        {
            Throw(SoundPackErrorKind.SizeLimitExceeded, $"Package file is too large: {file.Name}");
        }

        return file.Length;
    }

    public static void CopyRegularFile(string sourcePath, string destinationPath, long maximumBytes)
    {
        _ = ValidateRegularFile(sourcePath, maximumBytes);
        var destination = Path.GetFullPath(destinationPath);
        Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
        try
        {
            using var source = new FileStream(
                Path.GetFullPath(sourcePath),
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read,
                64 * 1_024,
                FileOptions.SequentialScan);
            if (source.Length < 0 || source.Length > maximumBytes)
            {
                Throw(SoundPackErrorKind.SizeLimitExceeded, "Source file grew beyond its safe copy limit.");
            }

            using var target = new FileStream(
                destination,
                FileMode.CreateNew,
                FileAccess.Write,
                FileShare.None,
                64 * 1_024,
                FileOptions.SequentialScan);
            var buffer = new byte[64 * 1_024];
            long copied = 0;
            while (true)
            {
                var read = source.Read(buffer);
                if (read == 0)
                {
                    break;
                }

                copied = checked(copied + read);
                if (copied > maximumBytes)
                {
                    Throw(SoundPackErrorKind.SizeLimitExceeded, "Source file grew beyond its safe copy limit.");
                }

                target.Write(buffer, 0, read);
            }
        }
        catch
        {
            try
            {
                if (File.Exists(destination))
                {
                    File.Delete(destination);
                }
            }
            catch (Exception cleanupError) when (cleanupError is IOException or UnauthorizedAccessException)
            {
            }
            throw;
        }
    }

    public static void EnsureSafeDirectory(string path, bool create)
    {
        var fullPath = Path.GetFullPath(path);
        if (create)
        {
            Directory.CreateDirectory(fullPath);
        }

        if (!Directory.Exists(fullPath))
        {
            Throw(SoundPackErrorKind.UnsafeFile, $"Missing directory: {fullPath}");
        }

        RejectReparsePoint(fullPath);
    }

    public static void RejectReparsePoint(string path)
    {
        var attributes = File.GetAttributes(path);
        if ((attributes & (FileAttributes.ReparsePoint | FileAttributes.Device)) != 0)
        {
            Throw(SoundPackErrorKind.UnsafeFile, $"Reparse points are not allowed: {path}");
        }
    }

    public static bool IsSameOrDescendant(string parentPath, string candidatePath)
    {
        var parent = CanonicalPath(parentPath);
        var candidate = CanonicalPath(candidatePath);
        return string.Equals(parent, candidate, StringComparison.OrdinalIgnoreCase) ||
            candidate.StartsWith(parent + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase);
    }

    public static void DeleteOwnedDirectory(string rootPath, string candidatePath, string requiredPrefix)
    {
        var root = CanonicalPath(rootPath);
        var candidate = CanonicalPath(candidatePath);
        if (!IsSameOrDescendant(root, candidate) ||
            string.Equals(root, candidate, StringComparison.OrdinalIgnoreCase) ||
            !Path.GetFileName(candidate).StartsWith(requiredPrefix, StringComparison.Ordinal))
        {
            Throw(SoundPackErrorKind.UnsafePath, "Refusing to remove an unowned directory.");
        }

        if (!Directory.Exists(candidate))
        {
            return;
        }

        RejectReparsePoint(candidate);
        Directory.Delete(candidate, recursive: true);
    }

    private static void Throw(SoundPackErrorKind kind, string message) =>
        throw new SoundPackException(kind, message);
}
