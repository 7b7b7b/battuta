namespace Battuta.TestSupport;

/// <summary>Shared xUnit trait values used to select safe and hardware-dependent suites.</summary>
public static class TestCategories
{
    public const string TraitName = "Category";
    public const string Core = "Core";
    public const string Integration = "Integration";
    public const string Ui = "UI";
    public const string Hardware = "Hardware";
    public const string Packaging = "Packaging";
    public const string Performance = "Performance";
}
