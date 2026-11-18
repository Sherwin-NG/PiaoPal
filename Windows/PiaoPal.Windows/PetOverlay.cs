using PiaoPal.Core;

namespace PiaoPal.Windows;

internal sealed class PetOverlay : Form
{
    private NativeFrame? presentedFrame;
    private Point presentedOrigin;
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
    protected override void OnHandleCreated(EventArgs e)
    {
        presentedFrame = null;
        base.OnHandleCreated(e);
    }
    protected override void OnVisibleChanged(EventArgs e)
    {
        presentedFrame = null;
        base.OnVisibleChanged(e);
    }
    protected override void OnDpiChanged(DpiChangedEventArgs e)
    {
        presentedFrame = null;
        base.OnDpiChanged(e);
    }
    /// <summary>Returns true when the requested frame is on screen. Transient GDI failures can retry next tick.</summary>
    internal bool Present(NativeFrame frame, DesktopPoint position, int baseSize, bool force = false)
    {
        if (force) presentedFrame = null;
        if(IsDisposed || !IsHandleCreated || frame.BitmapHandle==0) return false;
        if(!LayeredFramePlacement.TryOrigin(position.X-frame.Width/2d, position.Y+baseSize/2d-frame.Height, frame.Width, frame.Height, out int x, out int y))
            return false;
        var origin = new Point(x, y);
        // The atlas reuses immutable frame objects until the skin or pixel size changes.
        if (frame == presentedFrame && origin == presentedOrigin) return true;
        presentedFrame = null;
        nint screenDC=NativeMethods.GetDC(0);
        if(screenDC==0) return false;
        nint memoryDC=0, previous=0;
        try
        {
            memoryDC=NativeMethods.CreateCompatibleDC(screenDC);
            if(memoryDC==0) return false;
            previous=NativeMethods.SelectObject(memoryDC,frame.BitmapHandle);
            if(previous==0 || previous==new nint(-1)) return false;
            var point=new NativeMethods.Point(x,y);
            var source=new NativeMethods.Point(0,0);
            var size=new NativeMethods.Size(frame.Width,frame.Height);
            var blend=new NativeMethods.BlendFunction { Operation=0,Flags=0,Alpha=255,Format=1 };
            if(!NativeMethods.UpdateLayeredWindow(Handle,screenDC,ref point,ref size,memoryDC,ref source,0,ref blend,2))
                return false;
            presentedFrame = frame;
            presentedOrigin = origin;
            FramesRendered++;
            return true;
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
