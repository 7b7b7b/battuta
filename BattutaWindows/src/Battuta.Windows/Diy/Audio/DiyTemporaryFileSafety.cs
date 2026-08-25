using System.IO;

namespace Battuta.Windows.Diy.Audio;

internal static class DiyTemporaryFileSafety
{
    public static void DeleteDirectoryTree(string directoryPath)
    {
        var root = Path.GetFullPath(directoryPath);
        if (!Directory.Exists(root))
        {
            return;
        }

        RejectReparsePoint(root);
        var pending = new Stack<string>();
        pending.Push(root);
        while (pending.Count > 0)
        {
            var directory = pending.Pop();
            foreach (var entry in Directory.EnumerateFileSystemEntries(directory))
            {
                var attributes = File.GetAttributes(entry);
                if ((attributes & (FileAttributes.ReparsePoint | FileAttributes.Device)) != 0)
                {
                    throw new DiyAudioException("临时音频目录包含不安全的重解析点。");
                }

                if ((attributes & FileAttributes.Directory) != 0)
                {
                    pending.Push(entry);
                }
            }
        }

        Directory.Delete(root, recursive: true);
    }

    private static void RejectReparsePoint(string path)
    {
        if ((File.GetAttributes(path) & (FileAttributes.ReparsePoint | FileAttributes.Device)) != 0)
        {
            throw new DiyAudioException("临时音频目录是重解析点。");
        }
    }
}
