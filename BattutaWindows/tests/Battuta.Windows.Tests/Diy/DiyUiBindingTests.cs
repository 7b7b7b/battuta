using System.Windows;
using System.Windows.Controls;
using Battuta.Core.Audio;
using Battuta.TestSupport;
using Battuta.TestSupport.Threading;
using Battuta.Windows.Diy.Packages;
using Battuta.Windows.Diy.ViewModels;
using Battuta.Windows.Views.Diy;

namespace Battuta.Windows.Tests.Diy;

public sealed class DiyUiBindingTests
{
    [Fact]
    [Trait(TestCategories.TraitName, TestCategories.Ui)]
    public async Task InspectorAndWorkspaceUpdateTheEditorViewModel()
    {
        await StaTestHost.RunAsync(async () =>
        {
            using var root = new TemporaryDirectory();
            using var library = new DiySoundPackLibrary(root.Combine("library"));
            await using var viewModel = new DiySoundPackEditorViewModel(
                library,
                SwitchProfiles.MxBrown.Value,
                temporaryCacheParent: root.Path);
            await viewModel.LoadInitialStateAsync();

            var inspector = new SoundPackInspector { DataContext = viewModel };
            inspector.Measure(new Size(340, 760));
            inspector.Arrange(new Rect(0, 0, 340, 760));
            inspector.UpdateLayout();
            var nameBox = Assert.IsType<TextBox>(inspector.FindName("PackNameBox"));
            nameBox.Text = "Windows 本地化音色";
            Assert.Equal("Windows 本地化音色", viewModel.Manifest?.Name);
            Assert.True(viewModel.IsDirty);
            var slotPicker = Assert.IsType<ComboBox>(inspector.FindName("RecommendedSlotPicker"));
            Assert.Equal("R3 · A 行", slotPicker.SelectedItem?.ToString());

            var workspace = new SoundPackKeyboardWorkspace { DataContext = viewModel };
            workspace.Measure(new Size(700, 700));
            workspace.Arrange(new Rect(0, 0, 700, 700));
            workspace.UpdateLayout();
            var perKey = Assert.IsType<RadioButton>(workspace.FindName("PerKeyModeButton"));
            perKey.IsChecked = true;
            Assert.Equal(DiyEditorMappingMode.PerKey, viewModel.MappingMode);
        });
    }

}
