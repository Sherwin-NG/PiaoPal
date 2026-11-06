using System.Runtime.InteropServices;

namespace PiaoPal.Windows;

internal static class NativeMethods
{
    internal const int WsExLayered = 0x80000, WsExTransparent = 0x20, WsExToolWindow = 0x80, WsExNoActivate = 0x08000000;
    internal const int GwlExStyle = -20;
    internal const uint SwpNoActivate = 0x0010, SwpNoOwnerZOrder = 0x0200, SwpNoSize = 0x0001, SwpNoMove = 0x0002;
    internal static readonly nint HwndTopmost = new(-1);
    [StructLayout(LayoutKind.Sequential)] internal struct Point { internal int X, Y; internal Point(int x, int y) { X=x; Y=y; } }
    [StructLayout(LayoutKind.Sequential)] internal struct Size { internal int Width, Height; internal Size(int w,int h) { Width=w; Height=h; } }
    [StructLayout(LayoutKind.Sequential, Pack = 1)] internal struct BlendFunction { internal byte Operation, Flags, Alpha, Format; }
    [StructLayout(LayoutKind.Sequential)] internal struct BitmapInfoHeader
    {
        internal uint Size; internal int Width, Height; internal ushort Planes, BitCount;
        internal uint Compression, SizeImage; internal int XPelsPerMeter, YPelsPerMeter; internal uint ClrUsed, ClrImportant;
    }
    [StructLayout(LayoutKind.Sequential)] internal struct BitmapInfo { internal BitmapInfoHeader Header; internal uint Colors; }
    [DllImport("user32.dll", SetLastError=true)] internal static extern nint GetDC(nint window);
    [DllImport("user32.dll")] internal static extern int ReleaseDC(nint window, nint dc);
    [DllImport("gdi32.dll", SetLastError=true)] internal static extern nint CreateCompatibleDC(nint dc);
    [DllImport("gdi32.dll", SetLastError=true)] internal static extern nint CreateDIBSection(nint dc, ref BitmapInfo info, uint usage, out nint bits, nint section, uint offset);
    [DllImport("gdi32.dll")] internal static extern nint SelectObject(nint dc, nint obj);
    [DllImport("gdi32.dll")] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool DeleteObject(nint obj);
    [DllImport("gdi32.dll")] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool DeleteDC(nint dc);
    [DllImport("user32.dll", SetLastError=true)] [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool UpdateLayeredWindow(nint window,nint destDC,ref Point point,ref Size size,nint sourceDC,ref Point source,uint key,ref BlendFunction blend,uint flags);
    [DllImport("user32.dll", SetLastError=true)] [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool SetWindowPos(nint window,nint insertAfter,int x,int y,int width,int height,uint flags);
    [DllImport("user32.dll", EntryPoint="GetWindowLongW", SetLastError=true)] internal static extern int GetWindowLong(nint window,int index);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool IsWindow(nint window);
    [DllImport("user32.dll")] internal static extern uint GetDpiForWindow(nint window);
    [DllImport("user32.dll")] internal static extern nint MonitorFromPoint(Point point,uint flags);
    [DllImport("shcore.dll")] internal static extern int GetDpiForMonitor(nint monitor,int type,out uint x,out uint y);
}
