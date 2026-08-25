using Battuta.TestSupport;

namespace Battuta.Windows.Tests.Ui;

public sealed class ProductionUiDataGuardTests
{
    private static readonly string[] ForbiddenPreviewMarkers =
    [
        "DemoValues",
        "DemoCount(",
        "private static readonly string[] Apps",
        "var seed =",
        "Visual Studio Code",
        "Microsoft Edge",
        "Windows Terminal",
        "WPS Office",
        "2025年8月25日",
        "Shift、Command",
        "置信度 82%",
        "296 ms",
        "570 ms",
        "已是最新版 1.0.0",
        "TargetNullValue=}",
    ];

    [Fact]
    [Trait(TestCategories.TraitName, TestCategories.Ui)]
    public void ProductionViewsDoNotContainCapturedPreviewOrMacOnlyData()
    {
        var repositoryRoot = FindRepositoryRoot();
        var sourceRoots = new[]
        {
            Path.Combine(repositoryRoot, "BattutaWindows", "src", "Battuta.Windows", "Views"),
            Path.Combine(repositoryRoot, "BattutaWindows", "src", "Battuta.Windows", "Controls"),
        };
        var failures = new List<string>();

        foreach (var sourceRoot in sourceRoots)
        {
            foreach (var path in Directory.EnumerateFiles(sourceRoot, "*", SearchOption.AllDirectories)
                         .Where(IsUiSourceFile))
            {
                var source = File.ReadAllText(path);
                foreach (var marker in ForbiddenPreviewMarkers)
                {
                    if (source.Contains(marker, StringComparison.Ordinal))
                    {
                        failures.Add(
                            $"{Path.GetRelativePath(repositoryRoot, path)} contains forbidden marker '{marker}'.");
                    }
                }
            }
        }

        Assert.Empty(failures);
    }

    private static bool IsUiSourceFile(string path) =>
        path.EndsWith(".cs", StringComparison.OrdinalIgnoreCase)
        || path.EndsWith(".xaml", StringComparison.OrdinalIgnoreCase);

    private static string FindRepositoryRoot()
    {
        for (var current = new DirectoryInfo(AppContext.BaseDirectory);
             current is not null;
             current = current.Parent)
        {
            if (File.Exists(Path.Combine(current.FullName, "WINDOWS_PORTING_HANDOFF.md")))
            {
                return current.FullName;
            }
        }

        throw new DirectoryNotFoundException(
            $"Could not locate the Battuta repository above '{AppContext.BaseDirectory}'.");
    }
}
