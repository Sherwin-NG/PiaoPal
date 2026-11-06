using System.Net.Http.Headers;
using System.Text.Json;

namespace PiaoPal.Windows;

internal sealed record UpdateResult(bool Available,string? Version);
internal static class UpdateChecker
{
    internal const string ReleasePage="https://github.com/Sherwin-NG/PiaoPal/releases/latest";
    internal static async Task<UpdateResult> CheckAsync(CancellationToken cancellationToken)
    {
        using var client=new HttpClient {Timeout=TimeSpan.FromSeconds(15)};
        client.DefaultRequestHeaders.UserAgent.ParseAdd("PiaoPal/"+Program.Version);
        client.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/vnd.github+json"));
        using HttpResponseMessage response=await client.GetAsync("https://api.github.com/repos/Sherwin-NG/PiaoPal/releases/latest",cancellationToken);
        if(response.StatusCode==System.Net.HttpStatusCode.NotFound) return new(false,null);
        response.EnsureSuccessStatusCode();
        using var document=JsonDocument.Parse(await response.Content.ReadAsStringAsync(cancellationToken));
        var root=document.RootElement;
        if(root.GetProperty("draft").GetBoolean() || root.GetProperty("prerelease").GetBoolean()) return new(false,null);
        string remote=(root.GetProperty("tag_name").GetString() ?? "").TrimStart('v');
        if(!TryStableVersion(remote,out var candidate) || !TryStableVersion(Program.Version,out var local)) return new(false,null);
        return new(candidate>local,remote);
    }
    private static bool TryStableVersion(string input,out Version value)
    {
        value=new Version(0,0,0);
        string[] components=input.Split('.');
        return components.Length==3 && components.All(c=>c.Length>0 && c.All(ch=>ch>='0' && ch<='9')) && Version.TryParse(input,out value!);
    }
}
