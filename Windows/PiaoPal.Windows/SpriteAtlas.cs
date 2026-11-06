using System.ComponentModel;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using PiaoPal.Core;

namespace PiaoPal.Windows;

internal sealed class SpriteAtlas : IDisposable
{
    internal static readonly string[] SkinIds = ["piaopiao", "classic", "dog", "tora", "maia", "vaporwave"];
    private readonly Dictionary<string, Bitmap> sheets = new();
    private readonly Dictionary<(bool walk,int col,int row,int width,int height), NativeFrame> frames = new();
    private string cachedSkin = "";
    private int cachedSize;
    internal int SheetCount => sheets.Count;

    internal SpriteAtlas()
    {
        try
        {
            foreach (string id in SkinIds)
            {
                string file = Path.Combine(AppContext.BaseDirectory,"Resources","Sprites",id+(id=="piaopiao"?".png":".gif"));
                using Image image=Image.FromFile(file);
                if (image.Width%8!=0 || image.Height%4!=0 || image.Width/8!=image.Height/4)
                    throw new InvalidDataException($"Invalid sprite atlas: {id}");
                sheets.Add(id, new Bitmap(image));
            }
            using Image walking=Image.FromFile(Path.Combine(AppContext.BaseDirectory,"Resources","Sprites","piaopiao-walk.png"));
            if (walking.Width!=256 || walking.Height!=512) throw new InvalidDataException("Invalid PiaoPiao walking atlas.");
            sheets.Add("piaopiao-walk",new Bitmap(walking));
        }
        catch { Dispose(); throw; }
    }

    internal NativeFrame Frame(string skin, SpritePose pose, int size)
    {
        size=Math.Clamp(size,32,768);
        if (skin!=cachedSkin || size!=cachedSize) { ClearFrames(); cachedSkin=skin; cachedSize=size; }
        int height=(int)Math.Round(size*Math.Clamp(pose.BreathScale,1,1.03));
        var key=(pose.UsesWalkingAtlas,pose.Column,pose.Row,size,height);
        if (frames.TryGetValue(key,out NativeFrame? cached)) return cached;
        Bitmap sheet=sheets[pose.UsesWalkingAtlas?"piaopiao-walk":skin];
        if (pose.Columns<=0 || pose.Rows<=0 || pose.Column<0 || pose.Row<0 || pose.Column>=pose.Columns || pose.Row>=pose.Rows)
            throw new InvalidDataException("Invalid sprite frame index.");
        int cellWidth=sheet.Width/pose.Columns, cellHeight=sheet.Height/pose.Rows;
        // An extra two rows keep the foot-anchored breathing pose inside the layered surface.
        using var bitmap=new Bitmap(size,height,PixelFormat.Format32bppPArgb);
        using (Graphics g=Graphics.FromImage(bitmap))
        {
            g.Clear(Color.Transparent);
            g.CompositingMode=CompositingMode.SourceCopy;
            g.InterpolationMode=InterpolationMode.NearestNeighbor;
            g.PixelOffsetMode=PixelOffsetMode.Half;
            g.DrawImage(sheet,new Rectangle(0,0,size,height),new Rectangle(pose.Column*cellWidth,pose.Row*cellHeight,cellWidth,cellHeight),GraphicsUnit.Pixel);
        }
        var result=new NativeFrame(bitmap);
        frames.Add(key,result);
        return result;
    }

    internal Bitmap Preview(string skin)
    {
        var result=new Bitmap(64,64,PixelFormat.Format32bppPArgb);
        using Graphics g=Graphics.FromImage(result);
        g.InterpolationMode=InterpolationMode.NearestNeighbor; g.PixelOffsetMode=PixelOffsetMode.Half;
        Bitmap sheet=sheets[skin];
        g.DrawImage(sheet,new Rectangle(0,0,64,64),new Rectangle(sheet.Width/8*3,sheet.Height/4*3,sheet.Width/8,sheet.Height/4),GraphicsUnit.Pixel);
        return result;
    }

    private void ClearFrames() { foreach (NativeFrame frame in frames.Values) frame.Dispose(); frames.Clear(); }
    public void Dispose() { ClearFrames(); foreach(Bitmap sheet in sheets.Values) sheet.Dispose(); sheets.Clear(); }
}

internal sealed class NativeFrame : IDisposable
{
    internal nint BitmapHandle { get; private set; }
    internal int Width { get; }
    internal int Height { get; }
    internal int TransparentPixels { get; private set; }
    internal int VisiblePixels { get; private set; }
    internal NativeFrame(Bitmap bitmap)
    {
        Width=bitmap.Width; Height=bitmap.Height;
        var info=new NativeMethods.BitmapInfo { Header=new NativeMethods.BitmapInfoHeader {
            Size=(uint)Marshal.SizeOf<NativeMethods.BitmapInfoHeader>(),Width=Width,Height=-Height,Planes=1,BitCount=32,Compression=0 } };
        nint handle=NativeMethods.CreateDIBSection(0,ref info,0,out nint bits,0,0);
        if (handle==0) throw new Win32Exception(Marshal.GetLastWin32Error());
        BitmapHandle=handle;
        try
        {
            BitmapData data=bitmap.LockBits(new Rectangle(0,0,Width,Height),ImageLockMode.ReadOnly,PixelFormat.Format32bppPArgb);
            try
            {
                byte[] row=new byte[Width*4];
                for(int y=0;y<Height;y++)
                {
                    Marshal.Copy(data.Scan0+y*data.Stride,row,0,row.Length);
                    for(int x=3;x<row.Length;x+=4) {if(row[x]==0) TransparentPixels++; else VisiblePixels++;}
                    Marshal.Copy(row,0,bits+y*Width*4,row.Length);
                }
            }
            finally { bitmap.UnlockBits(data); }
        }
        catch { Dispose(); throw; }
    }
    public void Dispose() { if(BitmapHandle!=0) { NativeMethods.DeleteObject(BitmapHandle); BitmapHandle=0; } }
}
