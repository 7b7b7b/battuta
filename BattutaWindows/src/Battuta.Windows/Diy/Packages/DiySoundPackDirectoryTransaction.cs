using System.IO;
using Battuta.Core.SoundPacks;

namespace Battuta.Windows.Diy.Packages;

internal static class DiySoundPackDirectoryTransaction
{
    public static void Install(
        string stagingPath,
        string destinationPath,
        string transactionRoot,
        bool replaceExisting)
    {
        var staging = DiySoundPackFileSafety.CanonicalPath(stagingPath);
        var destination = DiySoundPackFileSafety.CanonicalPath(destinationPath);
        var root = DiySoundPackFileSafety.CanonicalPath(transactionRoot);
        if (!DiySoundPackFileSafety.IsSameOrDescendant(root, staging) ||
            !DiySoundPackFileSafety.IsSameOrDescendant(root, destination))
        {
            throw new SoundPackException(
                SoundPackErrorKind.UnsafePath,
                "Sound-pack transaction paths must share the declared parent.");
        }

        string? backup = null;
        try
        {
            if (Directory.Exists(destination))
            {
                if (!replaceExisting)
                {
                    throw new SoundPackException(
                        SoundPackErrorKind.PackAlreadyExists,
                        $"A package already exists at {destination}.");
                }

                DiySoundPackFileSafety.RejectReparsePoint(destination);
                backup = Path.Combine(
                    root,
                    $".backup-{Path.GetFileNameWithoutExtension(destination)}-{Guid.NewGuid():N}.simuboardpack");
                Directory.Move(destination, backup);
            }
            else if (File.Exists(destination))
            {
                throw new SoundPackException(
                    SoundPackErrorKind.UnsafeFile,
                    "A regular file occupies the sound-pack destination.");
            }

            Directory.Move(staging, destination);

            if (backup is not null && Directory.Exists(backup))
            {
                try
                {
                    DiySoundPackFileSafety.DeleteOwnedDirectory(root, backup, ".backup-");
                }
                catch (IOException)
                {
                    // The new package is installed and valid. A stale, hidden backup is
                    // safer than failing after commit and making the caller retry it.
                }
                catch (UnauthorizedAccessException)
                {
                }
            }
        }
        catch
        {
            if (Directory.Exists(destination) && backup is not null)
            {
                try
                {
                    DiySoundPackFileSafety.DeleteOwnedDirectory(root, destination, Path.GetFileName(destination));
                }
                catch (Exception cleanupError) when (
                    cleanupError is IOException or UnauthorizedAccessException or SoundPackException)
                {
                }
            }

            if (backup is not null && Directory.Exists(backup) && !Directory.Exists(destination))
            {
                Directory.Move(backup, destination);
            }

            throw;
        }
    }
}
