using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text.Json;
using Microsoft.Win32;
using PiaoPal.Core;

namespace PiaoPal.Windows;

internal sealed class PetApplicationContext : ApplicationContext
{
    private readonly LaunchOptions options;
    private readonly RunDiagnostics log;
    internal readonly SettingsStore Store;
    internal readonly PetMotion Motion=new();
    internal readonly SpriteAtlas Sprites;
    private readonly PetOverlay overlay;
    private readonly NotifyIcon tray;
    private readonly Icon appIcon;
    private readonly System.Windows.Forms.Timer timer=new() {Interval=16};
    private readonly Stopwatch clock=Stopwatch.StartNew();
    private readonly List<string> smokeChecks=[];
    private SettingsWindow? settings;
    private ContextMenuStrip? menu;
    private double lastFrame, lastSave, lastStats, lastSaveWarning=-300, lastFrameErrorLog=-30, smokeChildStarted;
    private Process? smokeChild;
    private int showRequests, smokeShowBaseline, smokeSessionBaseline;
    private bool stopped, suspended, systemSuspended, sessionLocked, trayDisposed, smokeCompleted;
    private int smokeStage;
    private string? smokeError;
    private long renderedFrames;
    internal Control Dispatcher { get; }=new Control();
    internal int ExitCode { get; private set; }
    internal bool English => Store.Settings.Language=="en";
    internal string T(string chinese,string english) => English?english:chinese;
    internal Icon AppIcon => appIcon;

    internal PetApplicationContext(LaunchOptions options,RunDiagnostics log)
    {
        this.options=options; this.log=log;
        Store=new SettingsStore(options.DataDirectory);
        if(Store.RecoveryMessage is string recovered) log.Write(recovered);
        Sprites=new SpriteAtlas();
        appIcon=new Icon(Path.Combine(AppContext.BaseDirectory,"app.ico"));
        overlay=new PetOverlay();
        _=Dispatcher.Handle;
        tray=new NotifyIcon {Icon=appIcon,Text="PiaoPal",Visible=true};
        tray.DoubleClick+=(_,_)=>ShowSettings();
        ApplyPreferences(false);
        RefreshScreens(true);
        overlay.Show();
        RebuildTray();
        SystemEvents.DisplaySettingsChanged+=DisplayChanged;
        SystemEvents.PowerModeChanged+=PowerChanged;
        SystemEvents.SessionSwitch+=SessionSwitched;
        SystemEvents.SessionEnding+=SessionEnding;
        timer.Tick+=OnTick;
        timer.Start();
        if(!options.IsSmoke && Store.Stats.SessionCount==1) ShowSettings();
    }

    internal void ShowSettings()
    {
        if(stopped) return;
        showRequests++;
        if(settings is null || settings.IsDisposed) settings=new SettingsWindow(this);
        if(!settings.Visible) settings.Show();
        if(settings.WindowState==FormWindowState.Minimized) settings.WindowState=FormWindowState.Normal;
        settings.BringToFront(); settings.Activate();
    }

    internal void ApplyPreferences(bool save=true)
    {
        Motion.Scale=Store.Settings.Scale; Motion.Speed=Store.Settings.Speed; Motion.SkinId=Store.Settings.SkinId;
        if(save)
        {
            try { Store.Save(); }
            catch(Exception error) when(error is IOException or UnauthorizedAccessException)
            {
                log.Write("save_failed "+error);
                if(!options.IsSmoke) MessageBox.Show(T("设置暂时无法保存，请检查个人数据目录是否可写。","Settings could not be saved. Please check your profile folder is writable."),"PiaoPal",MessageBoxButtons.OK,MessageBoxIcon.Warning);
                else throw;
            }
            RebuildTray(); settings?.RefreshLabels();
        }
    }

    internal void ToggleRest()
    {
        Motion.SetResting(!Motion.IsResting); RebuildTray(); settings?.RefreshLabels();
    }

    internal void FindPet()
    {
        RefreshScreens(true); if(!suspended) { overlay.Show(); overlay.EnsureTopmost(); }
    }

    private void RebuildTray()
    {
        var next=new ContextMenuStrip();
        next.Items.Add(T("打开飘伴设置","Open PiaoPal settings"),null,(_,_)=>ShowSettings());
        next.Items.Add(Motion.IsResting?T("唤醒伙伴","Wake companion"):T("让伙伴休息","Let companion rest"),null,(_,_)=>ToggleRest());
        next.Items.Add(T("找回伙伴","Bring companion here"),null,(_,_)=>FindPet());
        next.Items.Add(new ToolStripSeparator());
        next.Items.Add(T("退出飘伴","Quit PiaoPal"),null,(_,_)=>Shutdown("user_requested"));
        tray.ContextMenuStrip=next;
        var previous=menu; menu=next; previous?.Dispose();
        string label=string.IsNullOrWhiteSpace(Store.Settings.Nickname)?"PiaoPal":Store.Settings.Nickname+" · PiaoPal";
        tray.Text=label.Length<=63?label:label[..63];
    }

    private void OnTick(object? sender,EventArgs e)
    {
        if(stopped) return;
        try
        {
            double now=clock.Elapsed.TotalSeconds;
            double dt=now-lastFrame; lastFrame=now;
            if(!suspended)
            {
                var cursor=Cursor.Position;
                UpdateDpi(Motion.Position);
                var frame=Motion.Tick(Math.Clamp(dt,0,.1),new DesktopPoint(cursor.X,cursor.Y));
                Store.AddDistance(frame.DistancePoints);
                if(frame.StartedNap) Store.RecordNap();
                if(frame.StartedScratch) Store.RecordScratch();
                UpdateDpi(frame.Position);
                int size=(int)Math.Round(64*Motion.Scale*Motion.PixelsPerDip);
                if(!overlay.Present(Sprites.Frame(Store.Settings.SkinId,frame.Pose,size),Motion.Position,size))
                    NotePresentSkipped();
                if(now-lastStats>=1) { lastStats=now; settings?.RefreshStats(); overlay.EnsureTopmost(); }
            }
            if(now-lastSave>=30)
            {
                lastSave=now;
                if(!TrySave("interval")) WarnSaveFailed(now);
            }
            if(options.IsSmoke) SmokeTick(now);
        }
        catch(Exception error) { HandleFrameError(error); }
    }

    private void NotePresentSkipped()
    {
        double now=clock.Elapsed.TotalSeconds;
        if(now-lastFrameErrorLog<30) return;
        lastFrameErrorLog=now;
        log.Write("layered_present_skipped");
    }

    private void HandleFrameError(Exception error)
    {
        if(options.IsSmoke) { Fail(error); return; }
        double now=clock.Elapsed.TotalSeconds;
        if(now-lastFrameErrorLog<30) return;
        lastFrameErrorLog=now;
        log.Write("frame_skipped "+error.GetType().Name+" "+error.Message);
    }

    internal bool TrySave(string reason)
    {
        try { Store.Save(); log.Write("stats_saved reason="+reason); return true; }
        catch(Exception error) when(error is IOException or UnauthorizedAccessException or ObjectDisposedException)
        {
            log.Write("save_failed reason="+reason+" "+error.Message);
            return false;
        }
    }

    private void WarnSaveFailed(double now)
    {
        if(options.IsSmoke || now-lastSaveWarning<300) return;
        lastSaveWarning=now;
        tray.ShowBalloonTip(5000,"PiaoPal",T("相伴记录暂时无法保存，稍后会自动重试。","Your progress could not be saved right now. PiaoPal will retry."),ToolTipIcon.Warning);
    }

    private void UpdateDpi(DesktopPoint position)
    {
        if(!position.IsValid) return;
        var point=new NativeMethods.Point((int)position.X,(int)position.Y);
        nint monitor=NativeMethods.MonitorFromPoint(point,2);
        if(monitor!=0 && NativeMethods.GetDpiForMonitor(monitor,0,out uint dpi,out _)==0 && dpi>=48 && dpi<=768)
            Motion.PixelsPerDip=dpi/96d;
    }

    private void RefreshScreens(bool locate=false)
    {
        var screens=Screen.AllScreens.Select(s=>s.WorkingArea).Where(r=>r.Width>0 && r.Height>0)
            .Select(r=>new DesktopRect(r.X,r.Y,r.Width,r.Height)).ToArray();
        Motion.SetScreens(screens);
        suspended=systemSuspended || sessionLocked || screens.Length==0;
        if(suspended) { overlay.Hide(); return; }
        if(locate)
        {
            Point cursor=Cursor.Position; UpdateDpi(new DesktopPoint(cursor.X,cursor.Y));
            Motion.Relocate(new DesktopPoint(cursor.X+80*Motion.PixelsPerDip,cursor.Y+80*Motion.PixelsPerDip));
        }
        try
        {
            int size=(int)Math.Round(64*Motion.Scale*Motion.PixelsPerDip);
            _=overlay.Present(Sprites.Frame(Store.Settings.SkinId,Motion.GetPose(),size),Motion.Position,size);
        }
        catch(Exception error) { HandleFrameError(error); }
        log.Write("display_layout_refreshed screens="+screens.Length);
    }
    private void Dispatch(Action action)
    {
        if(stopped || Dispatcher.IsDisposed) return;
        try
        {
            Dispatcher.BeginInvoke((Action)(() =>
            {
                if(stopped) return;
                try { action(); }
                catch(Exception error) { HandleFrameError(error); }
            }));
        }
        catch(InvalidOperationException) when(stopped || Dispatcher.IsDisposed) { }
    }
    private void DisplayChanged(object? sender,EventArgs e) => Dispatch(()=> { RefreshScreens(); if(!suspended) overlay.Show(); });
    private void PowerChanged(object sender,PowerModeChangedEventArgs e) => Dispatch(()=>
        ApplyLifetime(e.Mode switch
        {
            PowerModes.Suspend => CompanionLifetimeEvent.Suspend,
            PowerModes.Resume => CompanionLifetimeEvent.Resume,
            _ => CompanionLifetimeEvent.Other
        }));
    private void SessionSwitched(object sender,SessionSwitchEventArgs e) => Dispatch(()=>
        ApplyLifetime(e.Reason switch
        {
            SessionSwitchReason.SessionLock or SessionSwitchReason.RemoteDisconnect or SessionSwitchReason.ConsoleDisconnect
                => CompanionLifetimeEvent.Lock,
            SessionSwitchReason.SessionUnlock or SessionSwitchReason.RemoteConnect or SessionSwitchReason.ConsoleConnect
                => CompanionLifetimeEvent.Unlock,
            SessionSwitchReason.SessionLogoff => CompanionLifetimeEvent.Logoff,
            _ => CompanionLifetimeEvent.Other
        }));
    private void ApplyLifetime(CompanionLifetimeEvent kind)
    {
        var reaction=CompanionLifetime.React(kind);
        if(reaction.SaveStats && !TrySave(kind.ToString())) WarnSaveFailed(clock.Elapsed.TotalSeconds);
        switch(kind)
        {
            case CompanionLifetimeEvent.Suspend:
                systemSuspended=true; log.Write("system_suspending"); break;
            case CompanionLifetimeEvent.Resume:
                systemSuspended=false; lastFrame=clock.Elapsed.TotalSeconds; log.Write("system_resumed"); break;
            case CompanionLifetimeEvent.Lock:
                sessionLocked=true; log.Write("session_locked"); break;
            case CompanionLifetimeEvent.Unlock:
                sessionLocked=false; lastFrame=clock.Elapsed.TotalSeconds; log.Write("session_unlocked"); break;
            case CompanionLifetimeEvent.Logoff:
                sessionLocked=true; log.Write("session_logoff"); break;
        }
        if(reaction.SuspendRendering) { suspended=true; overlay.Hide(); }
        if(reaction.ResumeRendering) { RefreshScreens(); if(!suspended) overlay.Show(); }
    }
    private void SessionEnding(object sender,SessionEndingEventArgs e)
    {
        if(stopped) return;
        if(!Dispatcher.InvokeRequired) { Shutdown("session_ending"); return; }
        var completed=new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        try
        {
            Dispatcher.BeginInvoke((Action)(()=>
            {
                try { Shutdown("session_ending"); }
                finally { completed.TrySetResult(true); }
            }));
            // Let the UI stop motion and flush before acknowledging Windows logoff.
            // A busy UI cannot hold up session ending indefinitely.
            if(completed.Task.Wait(TimeSpan.FromSeconds(2))) return;
            log.Write("session_end_ui_timeout; flushing statistics directly");
            TrySave("session_ending_timeout");
        }
        catch(ObjectDisposedException) { /* Normal shutdown already disposed the store/window. */ }
        catch(Exception error) when(error is IOException or UnauthorizedAccessException or InvalidOperationException)
        { log.Write("session_end_flush_failed "+error.Message); }
    }

    internal void Fail(Exception error)
    {
        ExitCode=1; smokeError=error.ToString(); log.Write("runtime_failure "+error);
        Shutdown("exception");
    }
    internal void Shutdown(string reason)
    {
        if(stopped) return;
        stopped=true; log.Write("termination_requested reason="+reason);
        timer.Stop(); timer.Dispose(); renderedFrames=overlay.FramesRendered;
        if(smokeChild is not null)
        {
            try { if(!smokeChild.HasExited) smokeChild.Kill(true); } catch(InvalidOperationException) { }
            smokeChild.Dispose(); smokeChild=null;
        }
        SystemEvents.DisplaySettingsChanged-=DisplayChanged;
        SystemEvents.PowerModeChanged-=PowerChanged;
        SystemEvents.SessionSwitch-=SessionSwitched;
        SystemEvents.SessionEnding-=SessionEnding;
        if(settings is not null && !settings.IsDisposed) settings.Dispose();
        tray.Visible=false; tray.Dispose(); trayDisposed=true;
        menu?.Dispose(); overlay.Dispose(); Sprites.Dispose(); appIcon.Dispose();
        try { Store.Dispose(); if(ExitCode==0) log.Finish(); }
        catch(Exception error) { ExitCode=1; smokeError=error.ToString(); log.Write("shutdown_save_failed "+error); }
        ExitThread();
    }
    protected override void Dispose(bool disposing)
    {
        if(disposing) { if(!stopped) Shutdown("application_dispose"); Dispatcher.Dispose(); }
        base.Dispose(disposing);
    }

    private void Check(bool value,string name)
    {
        if(!value) throw new InvalidOperationException("Smoke check failed: "+name);
        smokeChecks.Add(name);
    }
    private void SmokeTick(double elapsed)
    {
        if(smokeCompleted) return;
        if(smokeStage==0 && elapsed>=.15)
        {
            Check(NativeMethods.IsWindow(overlay.Handle),"native_overlay_handle");
            Check((NativeMethods.GetWindowLong(overlay.Handle,NativeMethods.GwlExStyle)&PetOverlay.RequiredStyles)==PetOverlay.RequiredStyles,"layered_clickthrough_noactivate_toolwindow");
            Check(!overlay.ShowInTaskbar && overlay.TopMost && overlay.Visible,"visible_topmost_without_taskbar");
            Check(overlay.FramesRendered>0,"native_layered_render");
            Check(Sprites.SheetCount==7,"all_bundled_sprite_sheets");
            foreach(string skin in SpriteAtlas.SkinIds)
            {
                foreach(PetAnimation animation in Enum.GetValues<PetAnimation>())
                {
                    var pose=SpriteAnimation.GetPose(animation,.5,.75,skin);
                    var rendered=Sprites.Frame(skin,pose,64);
                    Check(rendered.BitmapHandle!=0 && rendered.VisiblePixels>0 && rendered.TransparentPixels>0,"frame_"+skin+"_"+animation);
                }
            }
            if(options.SmokePhase=="seed") Check(Store.Settings.Scale==1,"fresh_default_scale_1x");
            else
            {
                Check(Store.Settings.Scale==1.5 && Store.Settings.Speed==2.5 && Store.Settings.SkinId=="dog" && Store.Settings.Nickname=="Smoke companion" && Store.Settings.Language=="en","preferences_survive_restart");
                Check(Store.Stats.DistancePoints>=1234.5 && Store.Stats.SessionCount>=2,"statistics_survive_restart");
            }
            ShowSettings();
            Check(settings is not null && settings.IsHandleCreated,"settings_window_created");
            settings!.Close(); smokeStage=1;
        }
        else if(smokeStage==1 && elapsed>=.4)
        {
            Check(!stopped && Application.MessageLoop && !overlay.IsDisposed && (settings is null || settings.IsDisposed),"closing_settings_keeps_pet_alive");
            smokeShowBaseline=showRequests; smokeSessionBaseline=Store.Stats.SessionCount;
            var start=new ProcessStartInfo(Path.Combine(AppContext.BaseDirectory,"PiaoPal.exe")) {UseShellExecute=false};
            start.ArgumentList.Add("--data-dir");
            start.ArgumentList.Add(Path.TrimEndingDirectorySeparator(options.DataDirectory)+Path.DirectorySeparatorChar);
            smokeChild=Process.Start(start) ?? throw new InvalidOperationException("Unable to start duplicate-instance check.");
            smokeChildStarted=elapsed; smokeStage=2;
        }
        else if(smokeStage==2)
        {
            if(elapsed-smokeChildStarted>10) throw new TimeoutException("Duplicate instance did not show settings within 10 seconds.");
            if(smokeChild is null || !smokeChild.HasExited || showRequests<=smokeShowBaseline) return;
            Check(smokeChild.ExitCode==0,"duplicate_process_exits_normally");
            Check(Store.Stats.SessionCount==smokeSessionBaseline && settings is {Visible:true},"duplicate_instance_reopens_existing_settings_without_new_session");
            smokeChild.Dispose(); smokeChild=null;
            if(options.SmokePhase=="seed")
            {
                settings!.ApplySmokePreferences();
                Check(Store.Settings.Scale==1.5 && Store.Settings.SkinId=="dog","settings_controls_apply_preferences");
                Store.AddDistance(1234.5);
            }
            smokeCompleted=true; Shutdown("smoke_normal_exit");
        }
    }
    internal void WriteSmokeResult()
    {
        if(options.SmokeOutput is not string output) return;
        bool success=ExitCode==0 && smokeCompleted && overlay.IsDisposed && trayDisposed;
        var data=new {
            success,phase=options.SmokePhase,version=Program.Version,
            processArchitecture=RuntimeInformation.ProcessArchitecture.ToString(),osArchitecture=RuntimeInformation.OSArchitecture.ToString(),
            checks=smokeChecks,framesRendered=renderedFrames,overlayDisposed=overlay.IsDisposed,trayDisposed,
            settings=new {scale=Store.Settings.Scale,speed=Store.Settings.Speed,skinId=Store.Settings.SkinId,nickname=Store.Settings.Nickname,language=Store.Settings.Language},
            stats=new {distancePoints=Store.Stats.DistancePoints,sessionCount=Store.Stats.SessionCount},error=smokeError
        };
        Directory.CreateDirectory(Path.GetDirectoryName(output)!);
        File.WriteAllText(output,JsonSerializer.Serialize(data,new JsonSerializerOptions {WriteIndented=true}));
        if(!success) ExitCode=1;
    }
}
