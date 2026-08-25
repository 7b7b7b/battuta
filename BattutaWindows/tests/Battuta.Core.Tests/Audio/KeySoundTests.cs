using Battuta.Core.Audio;
using Battuta.Core.Input;

namespace Battuta.Core.Tests.Audio;

public sealed class KeySoundTests
{
    [Fact]
    public void ProfileCatalogRetainsAllBuiltInIdsAndCapabilities()
    {
        Assert.Equal(20, SwitchProfileCatalog.All.Count);
        Assert.Equal(20, SwitchProfileCatalog.All.Select(profile => profile.Id.Value).Distinct().Count());
        Assert.All(SwitchProfileCatalog.All, profile => Assert.True(profile.SupportsReleaseSound));

        var noDedicatedSpecial = SwitchProfileCatalog.All
            .Where(profile => !profile.HasDedicatedSpecialKeySamples)
            .Select(profile => profile.Id.Value)
            .ToHashSet();
        Assert.Equal(
            new HashSet<string>
            {
                "mxblue", "mxclear", "studiotactile", "boxwhite",
                "lowprofileblue", "studioclicky", "keychronred",
            },
            noDedicatedSpecial);

        var rowSpecificRelease = SwitchProfileCatalog.All
            .Where(profile => profile.HasRowSpecificReleaseSamples)
            .Select(profile => profile.Id.Value)
            .ToHashSet();
        Assert.Equal(
            new HashSet<string>
            {
                "mxclear", "g915brown", "studiotactile", "boxwhite",
                "lowprofileblue", "studioclicky", "keychronred",
            },
            rowSpecificRelease);
    }

    [Theory]
    [MemberData(nameof(PressRowCases))]
    public void PressUsesExpectedKeyboardRow(PhysicalKeyId key, KeySoundSample expected)
    {
        var profile = SwitchProfileCatalog.Get(SwitchProfiles.MxBlue);
        Assert.Equal(expected, KeySoundMapper.SampleFor(key, KeySoundPhase.Press, profile));
    }

    public static TheoryData<PhysicalKeyId, KeySoundSample> PressRowCases => new()
    {
        { PhysicalKeys.Digit1, KeySoundSample.GenericR0 },
        { PhysicalKeys.KeyQ, KeySoundSample.GenericR1 },
        { PhysicalKeys.KeyA, KeySoundSample.GenericR2 },
        { PhysicalKeys.KeyZ, KeySoundSample.GenericR3 },
        { PhysicalKeys.Space, KeySoundSample.GenericR4 },
        { PhysicalKeys.Fn, KeySoundSample.GenericR4 },
    };

    [Fact]
    public void DedicatedSpecialSamplesBeatRows()
    {
        var profile = SwitchProfileCatalog.Get(SwitchProfiles.HolyPanda);

        Assert.Equal(KeySoundSample.Space,
            KeySoundMapper.SampleFor(PhysicalKeys.Space, KeySoundPhase.Press, profile));
        Assert.Equal(KeySoundSample.Enter,
            KeySoundMapper.SampleFor(PhysicalKeys.NumpadEnter, KeySoundPhase.Press, profile));
        Assert.Equal(KeySoundSample.Backspace,
            KeySoundMapper.SampleFor(PhysicalKeys.Delete, KeySoundPhase.Press, profile));
    }

    [Fact]
    public void ReleaseMappingMatchesProfileCapabilityCombinations()
    {
        var holyPanda = SwitchProfileCatalog.Get(SwitchProfiles.HolyPanda);
        Assert.Equal(KeySoundSample.Generic,
            KeySoundMapper.SampleFor(PhysicalKeys.KeyA, KeySoundPhase.Release, holyPanda));
        Assert.Equal(KeySoundSample.Space,
            KeySoundMapper.SampleFor(PhysicalKeys.Space, KeySoundPhase.Release, holyPanda));

        var mxClear = SwitchProfileCatalog.Get(SwitchProfiles.MxClear);
        Assert.Equal(KeySoundSample.GenericR2,
            KeySoundMapper.SampleFor(PhysicalKeys.KeyA, KeySoundPhase.Release, mxClear));
        Assert.Equal(KeySoundSample.GenericR4,
            KeySoundMapper.SampleFor(PhysicalKeys.Space, KeySoundPhase.Release, mxClear));

        var g915 = SwitchProfileCatalog.Get(SwitchProfiles.G915Brown);
        Assert.Equal(KeySoundSample.GenericR2,
            KeySoundMapper.SampleFor(PhysicalKeys.KeyA, KeySoundPhase.Release, g915));
        Assert.Equal(KeySoundSample.Space,
            KeySoundMapper.SampleFor(PhysicalKeys.Space, KeySoundPhase.Release, g915));

        var mxBlue = SwitchProfileCatalog.Get(SwitchProfiles.MxBlue);
        Assert.Equal(KeySoundSample.Generic,
            KeySoundMapper.SampleFor(PhysicalKeys.Space, KeySoundPhase.Release, mxBlue));
    }

    [Fact]
    public void RequiredSamplePlanExplainsBundledKeyboardResourceContract()
    {
        var total = SwitchProfileCatalog.All.Sum(profile =>
            BuiltInSamplePlan.RequiredSamples(profile, KeySoundPhase.Press).Count
            + BuiltInSamplePlan.RequiredSamples(profile, KeySoundPhase.Release).Count);

        Assert.Equal(226, total);
        Assert.Equal(8, BuiltInSamplePlan.RequiredSamples(
            SwitchProfileCatalog.Get(SwitchProfiles.G915Brown), KeySoundPhase.Release).Count);
        Assert.Equal(5, BuiltInSamplePlan.RequiredSamples(
            SwitchProfileCatalog.Get(SwitchProfiles.MxClear), KeySoundPhase.Release).Count);
        Assert.Equal([KeySoundSample.Generic], BuiltInSamplePlan.RequiredSamples(
            SwitchProfileCatalog.Get(SwitchProfiles.MxBlue), KeySoundPhase.Release));
    }

    [Fact]
    public void ResourceWireNamesRemainCompatible()
    {
        Assert.Equal("GENERIC_R2", KeySoundSample.GenericR2.ResourceName());
        Assert.Equal("BACKSPACE", KeySoundSample.Backspace.ResourceName());
        Assert.Equal("press", KeySoundPhase.Press.DirectoryName());
        Assert.Equal("release", KeySoundPhase.Release.DirectoryName());
    }

    [Fact]
    public void PointerButtonsRetainSampleFallbackAndPlaybackRates()
    {
        Assert.Equal(5, PointerSoundProfileCatalog.All.Count);
        Assert.Equal(PointerButton.Primary, PointerButton.FromButtonNumber(0));
        Assert.Equal(PointerButton.Secondary, PointerButton.FromButtonNumber(1));
        Assert.Equal(PointerButton.Middle, PointerButton.FromButtonNumber(2));
        Assert.Equal(PointerButton.Auxiliary(8), PointerButton.FromButtonNumber(8));
        Assert.Equal(PointerSoundSample.Secondary, PointerButton.Secondary.Sample);
        Assert.Equal(PointerSoundSample.Middle, PointerButton.Middle.Sample);
        Assert.Equal(PointerSoundSample.Middle, PointerButton.Auxiliary(8).Sample);
        Assert.Equal(0.97f, PointerButton.Secondary.PlaybackRate);
        Assert.Equal(1.04f, PointerButton.Middle.PlaybackRate);
        Assert.Equal(1.02f, PointerButton.Auxiliary(8).PlaybackRate);
    }
}
