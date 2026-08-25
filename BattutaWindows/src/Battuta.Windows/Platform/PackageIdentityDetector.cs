using System.Runtime.InteropServices;

namespace Battuta.Windows.Platform;

/// <summary>
/// Detects whether the current process has MSIX package identity without
/// referencing WinRT projections. This keeps the unpackaged build usable too.
/// </summary>
public static class PackageIdentityDetector
{
    private const int ErrorInsufficientBuffer = 122;
    private const int AppModelErrorNoPackage = 15700;

    public static PackageIdentityInfo GetCurrent()
    {
        if (!OperatingSystem.IsWindows())
        {
            return PackageIdentityInfo.Unpackaged;
        }

        var fullName = ReadPackageString(GetCurrentPackageFullName);
        if (fullName is null)
        {
            return PackageIdentityInfo.Unpackaged;
        }

        var familyName = ReadPackageString(GetCurrentPackageFamilyName);
        return new PackageIdentityInfo(true, fullName, familyName);
    }

    private static string? ReadPackageString(PackageStringReader reader)
    {
        var length = 0;
        var result = reader(ref length, null);
        if (result == AppModelErrorNoPackage)
        {
            return null;
        }

        if (result != ErrorInsufficientBuffer || length <= 1)
        {
            return null;
        }

        var buffer = new char[length];
        result = reader(ref length, buffer);
        return result == 0
            ? new string(buffer, 0, Math.Max(0, length - 1))
            : null;
    }

    private delegate int PackageStringReader(
        ref int packageNameLength,
        [Out] char[]? packageName);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetCurrentPackageFullName(
        ref int packageFullNameLength,
        [Out] char[]? packageFullName);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetCurrentPackageFamilyName(
        ref int packageFamilyNameLength,
        [Out] char[]? packageFamilyName);
}

public sealed record PackageIdentityInfo(
    bool IsPackaged,
    string? FullName,
    string? FamilyName)
{
    public static PackageIdentityInfo Unpackaged { get; } = new(false, null, null);
}
