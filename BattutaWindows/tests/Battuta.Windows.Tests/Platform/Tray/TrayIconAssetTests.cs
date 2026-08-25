using System.Buffers.Binary;
using System.Runtime.InteropServices;
using Battuta.TestSupport;
using Battuta.Windows.Tray;

namespace Battuta.Windows.Tests.Platform.Tray;

public sealed class TrayIconAssetTests
{
    private static readonly byte[] PngSignature = [137, 80, 78, 71, 13, 10, 26, 10];
    private static readonly int[] RequiredTraySizes = [16, 20, 24, 32];

    [Fact]
    [Trait(TestCategories.TraitName, TestCategories.Integration)]
    public void BundledIconContainsRequiredHighColorTrayFrames()
    {
        var iconPath = BundledIconPath();
        var bytes = File.ReadAllBytes(iconPath);
        var frames = ReadFrames(bytes);

        Assert.All(RequiredTraySizes, size =>
        {
            var candidates = frames.Where(frame => frame.Width == size && frame.Height == size).ToArray();
            Assert.NotEmpty(candidates);
            Assert.Contains(candidates, frame => frame.BitsPerPixel == 32 || frame.HasPngPayload);
        });
    }

    [Theory]
    [InlineData(16)]
    [InlineData(32)]
    [Trait(TestCategories.TraitName, TestCategories.Integration)]
    public void Win32LoadsVisibleAlphaPixelsAtTraySizes(int pixelSize)
    {
        var icon = NativeTrayIconService.LoadIconFromFile(BundledIconPath(), pixelSize);
        try
        {
            Assert.True(GetIconInfo(icon, out var info));
            try
            {
                Assert.NotEqual(IntPtr.Zero, info.ColorBitmap);
                Assert.True(
                    GetObjectNative(
                        info.ColorBitmap,
                        Marshal.SizeOf<NativeBitmap>(),
                        out var bitmap) > 0);
                Assert.Equal(pixelSize, bitmap.Width);
                Assert.Equal(pixelSize, Math.Abs(bitmap.Height));
                Assert.True(bitmap.BitsPerPixel >= 32);

                var pixels = ReadBgraPixels(info.ColorBitmap, bitmap.Width, Math.Abs(bitmap.Height));
                var visiblePixels = 0;
                for (var offset = 0; offset < pixels.Length; offset += 4)
                {
                    var blue = pixels[offset];
                    var green = pixels[offset + 1];
                    var red = pixels[offset + 2];
                    var alpha = pixels[offset + 3];
                    if (alpha > 0 && (red > 0 || green > 0 || blue > 0))
                    {
                        visiblePixels++;
                    }
                }

                Assert.True(
                    visiblePixels > 0,
                    $"The {pixelSize}px icon loaded successfully but every BGRA pixel was transparent.");
            }
            finally
            {
                if (info.ColorBitmap != IntPtr.Zero)
                {
                    Assert.True(DeleteObject(info.ColorBitmap));
                }

                if (info.MaskBitmap != IntPtr.Zero)
                {
                    Assert.True(DeleteObject(info.MaskBitmap));
                }
            }
        }
        finally
        {
            Assert.True(DestroyIcon(icon));
        }
    }

    private static string BundledIconPath() =>
        Path.Combine(AppContext.BaseDirectory, "Assets", "Battuta.ico");

    private static List<IconFrame> ReadFrames(ReadOnlySpan<byte> bytes)
    {
        Assert.True(bytes.Length >= 6);
        Assert.Equal((ushort)0, BinaryPrimitives.ReadUInt16LittleEndian(bytes));
        Assert.Equal((ushort)1, BinaryPrimitives.ReadUInt16LittleEndian(bytes[2..]));
        var frameCount = BinaryPrimitives.ReadUInt16LittleEndian(bytes[4..]);
        Assert.True(frameCount > 0);
        Assert.True(bytes.Length >= 6 + frameCount * 16);

        var result = new List<IconFrame>(frameCount);
        for (var index = 0; index < frameCount; index++)
        {
            var entry = bytes.Slice(6 + index * 16, 16);
            var width = entry[0] == 0 ? 256 : entry[0];
            var height = entry[1] == 0 ? 256 : entry[1];
            var bitsPerPixel = BinaryPrimitives.ReadUInt16LittleEndian(entry[6..]);
            var byteCount = checked((int)BinaryPrimitives.ReadUInt32LittleEndian(entry[8..]));
            var offset = checked((int)BinaryPrimitives.ReadUInt32LittleEndian(entry[12..]));
            Assert.InRange(offset, 0, bytes.Length);
            Assert.InRange(byteCount, 1, bytes.Length - offset);
            var payload = bytes.Slice(offset, byteCount);
            var png = payload.Length >= PngSignature.Length
                && payload[..PngSignature.Length].SequenceEqual(PngSignature);
            result.Add(new IconFrame(width, height, bitsPerPixel, png));
        }

        return result;
    }

    private static byte[] ReadBgraPixels(IntPtr bitmap, int width, int height)
    {
        var pixels = new byte[checked(width * height * 4)];
        var information = new BitmapInfo
        {
            Header = new BitmapInfoHeader
            {
                Size = (uint)Marshal.SizeOf<BitmapInfoHeader>(),
                Width = width,
                Height = -height,
                Planes = 1,
                BitsPerPixel = 32,
                Compression = 0,
            },
        };
        var deviceContext = GetDC(IntPtr.Zero);
        Assert.NotEqual(IntPtr.Zero, deviceContext);
        try
        {
            Assert.Equal(
                height,
                GetDIBits(
                    deviceContext,
                    bitmap,
                    0,
                    (uint)height,
                    pixels,
                    ref information,
                    0));
        }
        finally
        {
            Assert.Equal(1, ReleaseDC(IntPtr.Zero, deviceContext));
        }

        return pixels;
    }

    private sealed record IconFrame(
        int Width,
        int Height,
        int BitsPerPixel,
        bool HasPngPayload);

    [StructLayout(LayoutKind.Sequential)]
    private struct IconInfo
    {
        [MarshalAs(UnmanagedType.Bool)]
        public bool IsIcon;
        public uint HotspotX;
        public uint HotspotY;
        public IntPtr MaskBitmap;
        public IntPtr ColorBitmap;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeBitmap
    {
        public int Type;
        public int Width;
        public int Height;
        public int WidthBytes;
        public ushort Planes;
        public ushort BitsPerPixel;
        public IntPtr Bits;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct BitmapInfoHeader
    {
        public uint Size;
        public int Width;
        public int Height;
        public ushort Planes;
        public ushort BitsPerPixel;
        public uint Compression;
        public uint ImageSize;
        public int PixelsPerMeterX;
        public int PixelsPerMeterY;
        public uint ColorsUsed;
        public uint ColorsImportant;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct BitmapInfo
    {
        public BitmapInfoHeader Header;
        public uint Colors;
    }

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetIconInfo(IntPtr icon, out IconInfo iconInfo);

    [DllImport("gdi32.dll", EntryPoint = "GetObjectW", SetLastError = true)]
    private static extern int GetObjectNative(
        IntPtr nativeObject,
        int byteCount,
        out NativeBitmap bitmap);

    [DllImport("gdi32.dll", SetLastError = true)]
    private static extern int GetDIBits(
        IntPtr deviceContext,
        IntPtr bitmap,
        uint startScan,
        uint scanLineCount,
        [Out] byte[] pixels,
        ref BitmapInfo bitmapInformation,
        uint usage);

    [DllImport("user32.dll")]
    private static extern IntPtr GetDC(IntPtr window);

    [DllImport("user32.dll")]
    private static extern int ReleaseDC(IntPtr window, IntPtr deviceContext);

    [DllImport("gdi32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DeleteObject(IntPtr nativeObject);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyIcon(IntPtr icon);
}
