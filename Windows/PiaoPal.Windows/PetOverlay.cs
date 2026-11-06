using System.ComponentModel;
using System.Runtime.InteropServices;
using PiaoPal.Core;

namespace PiaoPal.Windows;

internal sealed class PetOverlay : Form
{
    internal long FramesRendered { get; private set; }
    internal const int RequiredStyles=NativeMethods.WsExLayered|NativeMethods.WsExTransparent|NativeMethods.WsExToolWindow|NativeMethods.WsExNoActivate;
    internal PetOverlay()
    {
        FormBorderStyle=FormBorderStyle.None; ShowInTaskbar=false; TopMost=true;
        AutoScaleMode=AutoScaleMode.None; StartPosition=FormStartPosition.Manual;
        Size=new Size(64,64); Text="PiaoPal Companion";
        SetStyle(ControlStyles.Selectable,false);
    }
    protected override bool ShowWithoutActivation => true;
    protected override CreateParams CreateParams { get { var p=base.CreateParams; p.ExStyle|=RequiredStyles; return p; } }
    protected override void WndProc(ref Message m)
    {
        if(m.Msg==0x0084) { m.Result=new nint(-1); return; } // HTTRANSPARENT
        if(m.Msg==0x0021) { m.Result=new nint(3); return; } // MA_NOACTIVATE
        base.WndProc(ref m);
    }
    internal void Present(NativeFrame frame, DesktopPoint position, int baseSize)
    {
        if(IsDisposed || !double.IsFinite(position.X) || !double.IsFinite(position.Y)) return;
        nint screenDC=NativeMethods.GetDC(0);
        if(screenDC==0) throw new Win32Exception(Marshal.GetLastWin32Error());
        nint memoryDC=0, previous=0;
        try
        {
            memoryDC=NativeMethods.CreateCompatibleDC(screenDC);
            if(memoryDC==0) throw new Win32Exception(Marshal.GetLastWin32Error());
            previous=NativeMethods.SelectObject(memoryDC,frame.BitmapHandle);
            if(previous==0 || previous==new nint(-1)) throw new Win32Exception(Marshal.GetLastWin32Error());
            var point=new NativeMethods.Point((int)Math.Round(position.X-frame.Width/2d),(int)Math.Round(position.Y+baseSize/2d-frame.Height));
            var source=new NativeMethods.Point(0,0);
            var size=new NativeMethods.Size(frame.Width,frame.Height);
            var blend=new NativeMethods.BlendFunction { Operation=0,Flags=0,Alpha=255,Format=1 };
            if(!NativeMethods.UpdateLayeredWindow(Handle,screenDC,ref point,ref size,memoryDC,ref source,0,ref blend,2))
                throw new Win32Exception(Marshal.GetLastWin32Error());
            FramesRendered++;
        }
        finally
        {
            if(memoryDC!=0) { if(previous!=0 && previous!=new nint(-1)) NativeMethods.SelectObject(memoryDC,previous); NativeMethods.DeleteDC(memoryDC); }
            NativeMethods.ReleaseDC(0,screenDC);
        }
    }
    internal void EnsureTopmost() => NativeMethods.SetWindowPos(Handle,NativeMethods.HwndTopmost,0,0,0,0,
        NativeMethods.SwpNoActivate|NativeMethods.SwpNoOwnerZOrder|NativeMethods.SwpNoMove|NativeMethods.SwpNoSize);
}
