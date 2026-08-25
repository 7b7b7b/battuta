using System.Drawing;
using System.Xml.Linq;

namespace Battuta.Windows.Tests.Packaging;

public sealed class PackagingContractTests
{
    private static readonly XNamespace Foundation =
        "http://schemas.microsoft.com/appx/manifest/foundation/windows10";
    private static readonly XNamespace Uap =
        "http://schemas.microsoft.com/appx/manifest/uap/windows10";
    private static readonly XNamespace Uap5 =
        "http://schemas.microsoft.com/appx/manifest/uap/windows10/5";
    private static readonly XNamespace Uap10 =
        "http://schemas.microsoft.com/appx/manifest/uap/windows10/10";
    private static readonly XNamespace AppInstaller =
        "http://schemas.microsoft.com/appx/appinstaller/2021";

    [Fact]
    public void MsixManifestDeclaresFullTrustDesktopAppAndSilentStartupTask()
    {
        var packagingRoot = GetPackagingRoot();
        var document = XDocument.Load(Path.Combine(packagingRoot, "Package.appxmanifest.template"));

        var package = Assert.IsType<XElement>(document.Root);
        var identity = Assert.Single(package.Elements(Foundation + "Identity"));
        Assert.Equal("{{PackageName}}", identity.Attribute("Name")?.Value);
        Assert.Equal("{{Publisher}}", identity.Attribute("Publisher")?.Value);
        Assert.Equal("{{PackageVersion}}", identity.Attribute("Version")?.Value);
        Assert.Equal("{{Architecture}}", identity.Attribute("ProcessorArchitecture")?.Value);

        var application = Assert.Single(
            package.Element(Foundation + "Applications")!.Elements(Foundation + "Application"));
        Assert.Equal("packagedClassicApp", application.Attribute(Uap10 + "RuntimeBehavior")?.Value);
        Assert.Equal("mediumIL", application.Attribute(Uap10 + "TrustLevel")?.Value);

        var visualElements = Assert.Single(application.Elements(Uap + "VisualElements"));
        Assert.Equal("键盘与点击音效", visualElements.Attribute("Description")?.Value);

        var resources = package
            .Element(Foundation + "Resources")!
            .Elements(Foundation + "Resource")
            .Select(element => element.Attribute("Language")?.Value)
            .ToArray();
        Assert.Equal(["zh-CN"], resources);

        var startupExtension = Assert.Single(
            application
                .Element(Foundation + "Extensions")!
                .Elements(Uap5 + "Extension"),
            element => element.Attribute("Category")?.Value == "windows.startupTask");
        Assert.Equal("--startup", startupExtension.Attribute(Uap10 + "Parameters")?.Value);
        var startupTask = Assert.Single(startupExtension.Elements(Uap5 + "StartupTask"));
        Assert.Equal("BattutaStartup", startupTask.Attribute("TaskId")?.Value);
        Assert.Equal("true", startupTask.Attribute("Enabled")?.Value);

        Assert.Empty(document.Descendants(Uap + "FileTypeAssociation"));
    }

    [Fact]
    public void AppInstallerTemplateUsesExactPackageIdentityAndNonBlockingUpdates()
    {
        var path = Path.Combine(GetPackagingRoot(), "Battuta.appinstaller.template");
        var document = XDocument.Load(path);
        var root = Assert.IsType<XElement>(document.Root);

        Assert.Equal("{{PackageVersion}}", root.Attribute("Version")?.Value);
        Assert.Equal("{{AppInstallerUri}}", root.Attribute("Uri")?.Value);
        var mainPackage = Assert.Single(root.Elements(AppInstaller + "MainPackage"));
        Assert.Equal("{{PackageName}}", mainPackage.Attribute("Name")?.Value);
        Assert.Equal("{{Publisher}}", mainPackage.Attribute("Publisher")?.Value);
        Assert.Equal("{{Architecture}}", mainPackage.Attribute("ProcessorArchitecture")?.Value);

        var onLaunch = Assert.Single(
            root
                .Element(AppInstaller + "UpdateSettings")!
                .Elements(AppInstaller + "OnLaunch"));
        Assert.Equal("0", onLaunch.Attribute("HoursBetweenUpdateChecks")?.Value);
        Assert.Equal("false", onLaunch.Attribute("UpdateBlocksActivation")?.Value);
    }

    [Theory]
    [InlineData("StoreLogo.png", 50, 50)]
    [InlineData("StoreBoxArt1080.png", 1080, 1080)]
    [InlineData("StoreListingIcon71.png", 71, 71)]
    [InlineData("StoreListingIcon150.png", 150, 150)]
    [InlineData("StoreListingIcon.png", 300, 300)]
    [InlineData("Square44x44Logo.png", 44, 44)]
    [InlineData("Square150x150Logo.png", 150, 150)]
    [InlineData("Wide310x150Logo.png", 310, 150)]
    public void MsixLogoHasRequiredPixelDimensions(string name, int width, int height)
    {
        var path = Path.Combine(GetPackagingRoot(), "Assets", name);
        using var image = Image.FromFile(path);

        Assert.Equal(width, image.Width);
        Assert.Equal(height, image.Height);
    }

    private static string GetPackagingRoot()
    {
        for (var current = new DirectoryInfo(AppContext.BaseDirectory);
             current is not null;
             current = current.Parent)
        {
            var candidate = Path.Combine(
                current.FullName,
                "BattutaWindows",
                "src",
                "Battuta.Packaging");
            if (File.Exists(Path.Combine(candidate, "Package.appxmanifest.template")))
            {
                return candidate;
            }
        }

        throw new DirectoryNotFoundException(
            $"Could not locate Battuta.Packaging above '{AppContext.BaseDirectory}'.");
    }
}
