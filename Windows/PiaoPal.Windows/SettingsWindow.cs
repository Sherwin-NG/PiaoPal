using System.Diagnostics;
using PiaoPal.Core;

namespace PiaoPal.Windows;

internal sealed class SettingsWindow : Form
{
    private sealed record Choice<T>(T Value,string Label) { public override string ToString()=>Label; }
    private readonly PetApplicationContext app;
    private readonly ComboBox pet=new() {DropDownStyle=ComboBoxStyle.DropDownList,Dock=DockStyle.Fill};
    private readonly TextBox nickname=new() {Dock=DockStyle.Fill,MaxLength=40};
    private readonly NumericUpDown scale=new() {Minimum=.5m,Maximum=3m,Increment=.1m,DecimalPlaces=1,Width=100};
    private readonly ComboBox speed=new() {DropDownStyle=ComboBoxStyle.DropDownList,Dock=DockStyle.Fill};
    private readonly ComboBox language=new() {DropDownStyle=ComboBoxStyle.DropDownList,Dock=DockStyle.Fill};
    private readonly PictureBox preview=new() {Width=80,Height=80,SizeMode=PictureBoxSizeMode.CenterImage};
    private readonly Label heading=new() {AutoSize=true,Font=new Font("Segoe UI",20,FontStyle.Bold)};
    private readonly Label subtitle=new() {AutoSize=true,ForeColor=Color.FromArgb(96,101,110)};
    private readonly Label petLabel=new(),nameLabel=new(),sizeLabel=new(),speedLabel=new(),languageLabel=new();
    private readonly Label stats=new() {AutoSize=true,Dock=DockStyle.Fill,Padding=new Padding(14),BackColor=Color.FromArgb(242,246,244)};
    private readonly Label hint=new() {AutoSize=true,MaximumSize=new Size(440,0),ForeColor=Color.FromArgb(96,101,110)};
    private readonly Label updateStatus=new() {AutoSize=true,MaximumSize=new Size(420,0),ForeColor=Color.FromArgb(96,101,110)};
    private readonly Button rest=new() {AutoSize=true},find=new() {AutoSize=true},checkUpdate=new() {AutoSize=true},download=new() {AutoSize=true,Visible=false},quit=new() {AutoSize=true};
    private readonly CancellationTokenSource cancellation=new();
    private bool loading, resourcesDisposed;

    internal SettingsWindow(PetApplicationContext app)
    {
        this.app=app;
        Icon=app.AppIcon; Text="飘伴 PiaoPal";
        Font=new Font("Segoe UI",10); BackColor=Color.White;
        StartPosition=FormStartPosition.CenterScreen; MinimumSize=new Size(500,600); ClientSize=new Size(520,610);
        AutoScaleMode=AutoScaleMode.Dpi;
        var scroll=new Panel {Dock=DockStyle.Fill,AutoScroll=true}; Controls.Add(scroll);
        var grid=new TableLayoutPanel {Dock=DockStyle.Top,AutoSize=true,Padding=new Padding(24),ColumnCount=2};
        grid.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute,106)); grid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100)); scroll.Controls.Add(grid);
        var header=new FlowLayoutPanel {AutoSize=true,Dock=DockStyle.Fill,WrapContents=false,Margin=new Padding(0,0,0,18)};
        var titles=new FlowLayoutPanel {AutoSize=true,FlowDirection=FlowDirection.TopDown,WrapContents=false,Padding=new Padding(6,9,0,0)};
        titles.Controls.Add(heading); titles.Controls.Add(subtitle); header.Controls.Add(preview); header.Controls.Add(titles);
        AddFull(grid,header);
        AddRow(grid,petLabel,pet); AddRow(grid,nameLabel,nickname);
        var sizePanel=new FlowLayoutPanel {AutoSize=true,Dock=DockStyle.Fill,Margin=new Padding(0)};
        sizePanel.Controls.Add(scale); sizePanel.Controls.Add(new Label {Text="×",AutoSize=true,Margin=new Padding(5,7,0,0)});
        AddRow(grid,sizeLabel,sizePanel); AddRow(grid,speedLabel,speed); AddRow(grid,languageLabel,language);
        stats.Margin=new Padding(0,16,0,14); AddFull(grid,stats);
        var actions=new FlowLayoutPanel {AutoSize=true,Dock=DockStyle.Fill,Margin=new Padding(0,0,0,12)};
        actions.Controls.Add(rest); actions.Controls.Add(find); AddFull(grid,actions);
        AddFull(grid,hint);
        var updates=new FlowLayoutPanel {AutoSize=true,Dock=DockStyle.Fill,Margin=new Padding(0,18,0,4)};
        updates.Controls.Add(checkUpdate); updates.Controls.Add(download); AddFull(grid,updates); AddFull(grid,updateStatus);
        var footer=new FlowLayoutPanel {AutoSize=true,Dock=DockStyle.Fill,FlowDirection=FlowDirection.RightToLeft,Margin=new Padding(0,18,0,0)};
        footer.Controls.Add(quit);
        var github=new LinkLabel {Text="GitHub",AutoSize=true,Margin=new Padding(12,8,12,0)};
        github.LinkClicked+=(_,_)=>OpenReleasePage(); footer.Controls.Add(github); AddFull(grid,footer);
        RefreshLabels();
        loading=true; nickname.Text=app.Store.Settings.Nickname; scale.Value=(decimal)app.Store.Settings.Scale; loading=false;
        pet.SelectedIndexChanged+=(_,_)=>SaveValues(); scale.ValueChanged+=(_,_)=>SaveValues();
        speed.SelectedIndexChanged+=(_,_)=>SaveValues(); language.SelectedIndexChanged+=(_,_)=>SaveValues();
        nickname.TextChanged+=(_,_)=> {if(!loading) app.Store.Settings.Nickname=nickname.Text.Trim();};
        nickname.Validated+=(_,_)=>SaveValues();
        rest.Click+=(_,_)=>app.ToggleRest(); find.Click+=(_,_)=>app.FindPet();
        quit.Click+=(_,_)=> {SaveValues(); app.Shutdown("user_requested");};
        checkUpdate.Click+=async (_,_)=>await CheckUpdates(); download.Click+=(_,_)=>OpenReleasePage();
        FormClosing+=(_,_)=>SaveValues();
        Deactivate+=(_,_)=>app.TrySave("settings_resign");
        RefreshStats();
    }
    private static void AddRow(TableLayoutPanel grid,Label label,Control value)
    {
        int row=grid.RowCount++; grid.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        label.AutoSize=true; label.Margin=new Padding(0,8,10,12);
        value.Margin=new Padding(0,4,0,10); grid.Controls.Add(label,0,row); grid.Controls.Add(value,1,row);
    }
    private static void AddFull(TableLayoutPanel grid,Control control)
    {
        int row=grid.RowCount++; grid.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        grid.Controls.Add(control,0,row); grid.SetColumnSpan(control,2);
    }
    internal void RefreshLabels()
    {
        if(IsDisposed) return;
        loading=true;
        try
        {
            Text=app.T("飘伴 PiaoPal","PiaoPal"); heading.Text=app.T("飘伴","PiaoPal");
            subtitle.Text=app.T("你的桌面伙伴","Your desktop companion")+" · "+Program.Version;
            petLabel.Text=app.T("伙伴","Companion"); nameLabel.Text=app.T("昵称","Nickname");
            sizeLabel.Text=app.T("大小","Size"); speedLabel.Text=app.T("速度","Speed"); languageLabel.Text=app.T("语言","Language");
            string[] names=app.English?["PiaoPiao","TuanTuan","Dodo","BanBan","TaoTao","MuMu"]:["飘飘","团团","豆豆","斑斑","桃桃","暮暮"];
            SetChoices(pet,SpriteAtlas.SkinIds.Select((id,i)=>new Choice<string>(id,names[i])),app.Store.Settings.SkinId);
            SetChoices(speed,new[] {new Choice<double>(.4,app.T("慵懒 · 0.4×","Leisurely · 0.4×")),new Choice<double>(1,app.T("标准 · 1×","Standard · 1×")),new Choice<double>(2.5,app.T("极速 · 2.5×","Fast · 2.5×"))},app.Store.Settings.Speed);
            SetChoices(language,new[] {new Choice<string>("zh-CN","简体中文"),new Choice<string>("en","English")},app.Store.Settings.Language);
            rest.Text=app.Motion.IsResting?app.T("唤醒伙伴","Wake companion"):app.T("让伙伴休息","Let companion rest");
            find.Text=app.T("找回伙伴","Bring companion here");
            checkUpdate.Text=app.T("检查更新","Check for updates"); download.Text=app.T("前往下载","Open download page"); quit.Text=app.T("退出飘伴","Quit PiaoPal");
            hint.Text=app.T("关闭这个窗口后，伙伴仍会留在桌面。双击任务栏通知区域的飘伴图标，可再次打开设置。","Your companion stays on the desktop when you close this window. Double-click the PiaoPal tray icon to open settings again.");
            UpdatePreview(); RefreshStats();
        }
        finally {loading=false;}
    }
    private static void SetChoices<T>(ComboBox box,IEnumerable<Choice<T>> choices,T selected)
    {
        box.BeginUpdate(); box.Items.Clear();
        foreach(var item in choices) box.Items.Add(item);
        box.SelectedItem=box.Items.Cast<Choice<T>>().FirstOrDefault(c=>EqualityComparer<T>.Default.Equals(c.Value,selected));
        box.EndUpdate();
    }
    private void UpdatePreview()
    {
        Image? old=preview.Image; preview.Image=app.Sprites.Preview(app.Store.Settings.SkinId); old?.Dispose();
    }
    private void SaveValues()
    {
        if(loading || IsDisposed) return;
        var state=app.Store.Settings;
        state.Nickname=nickname.Text.Trim(); state.Scale=(double)scale.Value;
        if(pet.SelectedItem is Choice<string> companion) state.SkinId=companion.Value;
        if(speed.SelectedItem is Choice<double> pace) state.Speed=pace.Value;
        if(language.SelectedItem is Choice<string> lang) state.Language=lang.Value;
        app.ApplyPreferences();
    }
    internal void RefreshStats()
    {
        if(IsDisposed) return;
        PetStats value=app.Store.Stats;
        stats.Text=app.T($"等级 {value.Level}  ·  已走 {value.DistanceMeters:0.0} 米\n连续相伴 {value.Streak} 天  ·  小睡 {value.Naps} 次\n已启动 {value.SessionCount} 次",
            $"Level {value.Level}  ·  {value.DistanceMeters:0.0} m walked\n{value.Streak} day streak  ·  {value.Naps} naps\n{value.SessionCount} sessions");
    }
    private async Task CheckUpdates()
    {
        checkUpdate.Enabled=false; download.Visible=false; updateStatus.Text=app.T("正在检查…","Checking…");
        try
        {
            UpdateResult result=await UpdateChecker.CheckAsync(cancellation.Token);
            if(IsDisposed) return;
            updateStatus.Text=result.Available?app.T($"发现新版本 {result.Version}",$"Version {result.Version} is available"):app.T("已经是最新版本","You're up to date");
            download.Visible=result.Available;
        }
        catch(OperationCanceledException) when(cancellation.IsCancellationRequested) { }
        catch(Exception error) when(error is HttpRequestException or TaskCanceledException or System.Text.Json.JsonException or KeyNotFoundException or InvalidOperationException)
        {
            if(!IsDisposed) updateStatus.Text=app.T("暂时无法检查，请稍后再试。","Unable to check right now. Please try again later.");
        }
        finally { if(!IsDisposed) checkUpdate.Enabled=true; }
    }
    private void OpenReleasePage()
    {
        try { Process.Start(new ProcessStartInfo(UpdateChecker.ReleasePage) {UseShellExecute=true}); }
        catch(Exception error) when(error is System.ComponentModel.Win32Exception or InvalidOperationException)
        {
            MessageBox.Show(UpdateChecker.ReleasePage,"PiaoPal",MessageBoxButtons.OK,MessageBoxIcon.Information);
        }
    }
    internal void ApplySmokePreferences()
    {
        loading=true;
        try
        {
            nickname.Text="Smoke companion"; scale.Value=1.5m;
            pet.SelectedItem=pet.Items.Cast<Choice<string>>().Single(c=>c.Value=="dog");
            speed.SelectedItem=speed.Items.Cast<Choice<double>>().Single(c=>c.Value==2.5);
            language.SelectedItem=language.Items.Cast<Choice<string>>().Single(c=>c.Value=="en");
        }
        finally {loading=false;}
        SaveValues();
    }
    protected override void Dispose(bool disposing)
    {
        if(disposing && !resourcesDisposed) {resourcesDisposed=true; cancellation.Cancel(); cancellation.Dispose(); preview.Image?.Dispose(); preview.Image=null;}
        base.Dispose(disposing);
    }
}
