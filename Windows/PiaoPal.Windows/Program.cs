using System.IO.Pipes;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace PiaoPal.Windows;

internal sealed record LaunchOptions(string DataDirectory, string? SmokeOutput, string SmokePhase)
{
    internal bool IsSmoke => SmokeOutput is not null;
    internal static LaunchOptions Parse(string[] args)
    {
        string? directory=null, smoke=null;
        string phase="seed";
        for(int i=0;i<args.Length;i++)
        {
            if(i+1>=args.Length) throw new ArgumentException($"Missing value for {args[i]}.");
            string value=args[++i];
            switch(args[i-1])
            {
                case "--data-dir": directory=Path.GetFullPath(value); break;
                case "--smoke-test": smoke=Path.GetFullPath(value); break;
                case "--smoke-phase": phase=value; break;
                default: throw new ArgumentException($"Unknown argument: {args[i-1]}");
            }
        }
        if(phase is not ("seed" or "verify")) throw new ArgumentException("Smoke phase must be seed or verify.");
        if(smoke is not null && directory is null) throw new ArgumentException("Smoke tests require an explicit isolated --data-dir.");
        directory ??= Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"PiaoPal");
        return new(directory,smoke,phase);
    }
}

internal static class Program
{
    internal static string Version => typeof(Program).Assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion.Split('+')[0] ?? "0.2.1";
    [STAThread]
    private static int Main(string[] args)
    {
        LaunchOptions? options=null;
        RunDiagnostics? log=null;
        PetApplicationContext? context=null;
        try
        {
            options=LaunchOptions.Parse(args);
            ApplicationConfiguration.Initialize();
            using var instance=new InstanceCoordinator(options.DataDirectory);
            if(!instance.IsPrimary) return instance.ShowPrimary() ? 0 : 1;
            log=new RunDiagnostics(options.DataDirectory);
            log.Write("launch_attempt");
            Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
            Application.ThreadException += (_,e) =>
            {
                log.Write("ui_exception "+e.Exception);
                Environment.ExitCode=1;
                context?.Fail(e.Exception);
            };
            AppDomain.CurrentDomain.UnhandledException += (_,e) => log.Write("unhandled_exception "+e.ExceptionObject);
            context=new PetApplicationContext(options,log);
            log.MarkRunning();
            instance.Start(context.Dispatcher,context.ShowSettings);
            Application.Run(context);
            context.Dispose();
            if(options.IsSmoke) context.WriteSmokeResult();
            return context.ExitCode;
        }
        catch(Exception error)
        {
            log?.Write("startup_failure "+error);
            if(options?.SmokeOutput is string output)
            {
                Directory.CreateDirectory(Path.GetDirectoryName(output)!);
                File.WriteAllText(output,JsonSerializer.Serialize(new {success=false,phase=options.SmokePhase,error=error.ToString(),version=Version}));
            }
            else MessageBox.Show("飘伴未能启动，请检查应用文件是否完整。\nPiaoPal could not start. Please extract the entire ZIP.\n\n"+error.Message,"PiaoPal",MessageBoxButtons.OK,MessageBoxIcon.Error);
            return 1;
        }
        finally { context?.Dispose(); }
    }
}

internal sealed class InstanceCoordinator : IDisposable
{
    private readonly Mutex mutex;
    private readonly string name;
    private readonly CancellationTokenSource cancellation=new();
    private NamedPipeServerStream? server;
    internal bool IsPrimary { get; }
    internal InstanceCoordinator(string directory)
    {
        name="PiaoPal-"+Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(Path.TrimEndingDirectorySeparator(Path.GetFullPath(directory)).ToUpperInvariant())))[..24];
        mutex=new Mutex(true,"Local\\"+name,out bool created); IsPrimary=created;
    }
    internal bool ShowPrimary()
    {
        try
        {
            using var pipe=new NamedPipeClientStream(".",name,PipeDirection.Out,PipeOptions.CurrentUserOnly);
            pipe.Connect(5000);
            using var writer=new StreamWriter(pipe,Encoding.UTF8,leaveOpen:true) {AutoFlush=true};
            writer.WriteLine("show");
            return true;
        }
        catch(IOException) { return false; }
        catch(TimeoutException) { return false; }
    }
    internal void Start(Control dispatcher,Action show)
    {
        _=Task.Run(async () =>
        {
            while(!cancellation.IsCancellationRequested)
            {
                try
                {
                    using var pipe=new NamedPipeServerStream(name,PipeDirection.In,1,PipeTransmissionMode.Byte,PipeOptions.Asynchronous|PipeOptions.CurrentUserOnly);
                    server=pipe;
                    await pipe.WaitForConnectionAsync(cancellation.Token);
                    using var timeout=CancellationTokenSource.CreateLinkedTokenSource(cancellation.Token);
                    timeout.CancelAfter(TimeSpan.FromSeconds(5));
                    using var reader=new StreamReader(pipe,Encoding.UTF8);
                    string? command=await reader.ReadLineAsync(timeout.Token);
                    if(command=="show" && !dispatcher.IsDisposed) dispatcher.BeginInvoke(show);
                }
                catch(OperationCanceledException) { }
                catch(ObjectDisposedException) when(cancellation.IsCancellationRequested) { }
                catch(IOException) { }
                catch(InvalidOperationException) when(cancellation.IsCancellationRequested || dispatcher.IsDisposed) { }
                finally { server=null; }
            }
        });
    }
    public void Dispose()
    {
        cancellation.Cancel(); server?.Dispose();
        if(IsPrimary) mutex.ReleaseMutex();
        mutex.Dispose(); cancellation.Dispose();
    }
}

internal sealed class RunDiagnostics
{
    private readonly string directory, session=Guid.NewGuid().ToString("N");
    private readonly object gate=new();
    private string Marker => Path.Combine(directory,"active-session.json");
    internal RunDiagnostics(string directory) { this.directory=directory; Directory.CreateDirectory(directory); }
    internal void Write(string message)
    {
        try
        {
            lock(gate)
            {
                string path=Path.Combine(directory,"lifecycle.log");
                if(File.Exists(path) && new FileInfo(path).Length>1_000_000) File.Move(path,path+".previous",true);
                File.AppendAllText(path,$"{DateTimeOffset.Now:O} pid={Environment.ProcessId} version={Program.Version} session={session} {message}{Environment.NewLine}");
            }
        }
        catch(IOException) { }
        catch(UnauthorizedAccessException) { }
    }
    internal void MarkRunning()
    {
        if(File.Exists(Marker)) Write("previous_run_missing_normal_exit; possible causes include force quit or power loss; not proof of a crash");
        File.WriteAllText(Marker,JsonSerializer.Serialize(new {session,pid=Environment.ProcessId,version=Program.Version}));
        Write("running");
    }
    internal void Finish()
    {
        try
        {
            if(File.Exists(Marker))
            {
                using var value=JsonDocument.Parse(File.ReadAllText(Marker));
                if(value.RootElement.TryGetProperty("session",out var owner) && owner.GetString()==session) File.Delete(Marker);
            }
        }
        catch(Exception error) when(error is IOException or UnauthorizedAccessException or JsonException) { Write("marker_cleanup_failed "+error.Message); }
        Write("termination_completed");
    }
}
