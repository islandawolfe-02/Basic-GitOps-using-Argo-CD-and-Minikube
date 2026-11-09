// Supplied foundation page and board API: W1.10 observe release (also packaged in Project 1).
// Read-only teaching equipment. Things to notice:
//   Release              packaged release label compiled into the image/DLL
//   LAB_ENV              public runtime label (runtime.env); LAB_SESSION labels this workspace's log stream
//   /api/boards/{id}     reference -> 200 board; slow / overdue -> the same board after a deterministic delay;
//                        anything else -> 404 NOT_FOUND
//   completion record    one JSON line per request on stdout, also pushed to Loki when LOCAL_LOKI_URL is set
using System.Diagnostics;
using System.Text;
using System.Text.Json;

const string Release = "foundation-observe-a";
const string Job = "academy-w110";

var builder = WebApplication.CreateBuilder(args);
builder.Logging.ClearProviders();          // stdout carries only the structured completion records
var app = builder.Build();

string environmentLabel = Environment.GetEnvironmentVariable("LAB_ENV") ?? "unset";
string session = Environment.GetEnvironmentVariable("LAB_SESSION") ?? "local";
string? lokiUrl = Environment.GetEnvironmentVariable("LOCAL_LOKI_URL");
string referenceBoard = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "data", "board-reference.json"));
var lokiClient = new HttpClient { Timeout = TimeSpan.FromSeconds(2) };

// Deterministic timing fixtures (milliseconds of server processing before the board is written).
var delays = new Dictionary<string, int> { ["reference"] = 0, ["slow"] = 300, ["overdue"] = 900 };

Console.WriteLine($"READY release={Release} environment={environmentLabel} session={session}");

// Completion recorder: wraps every request, then writes one bounded JSON record (no bodies, no credentials).
app.Use(async (context, next) =>
{
    var clock = Stopwatch.StartNew();
    string requestId = context.Request.Headers["X-Request-Id"].FirstOrDefault() ?? Guid.NewGuid().ToString();
    string actionId = context.Request.Headers["X-Action-Id"].FirstOrDefault() ?? "";
    context.Response.Headers["X-Lab-Release"] = Release;
    context.Response.Headers["X-Lab-Environment"] = environmentLabel;
    context.Response.Headers["X-Request-Id"] = requestId;   // echo the caller's attempt identifier
    try
    {
        await next();
    }
    finally
    {
        clock.Stop();
        var record = new Dictionary<string, object?>
        {
            ["ts"] = DateTime.UtcNow.ToString("O"),
            ["job"] = Job,
            ["session"] = session,
            ["request_id"] = requestId,
            ["action_id"] = actionId,
            ["method"] = context.Request.Method,
            ["path"] = context.Request.Path.Value,
            ["status"] = context.Response.StatusCode,
            ["result_status"] = context.Items.TryGetValue("result_status", out var r) ? r : null,
            ["response_status"] = context.Response.StatusCode,
            ["duration_ms"] = clock.ElapsedMilliseconds,
            ["elapsed_ms"] = clock.ElapsedMilliseconds,
            ["caller_aborted"] = context.RequestAborted.IsCancellationRequested,
            ["release"] = Release,
            ["environment"] = environmentLabel,
        };
        string line = JsonSerializer.Serialize(record);
        Console.WriteLine(line);
        if (!string.IsNullOrEmpty(lokiUrl)) _ = PushToLoki(line);
    }
});

app.UseDefaultFiles();
app.UseStaticFiles(new StaticFileOptions
{
    // client.json is configuration: never let the browser reuse an old copy.
    OnPrepareResponse = ctx => ctx.Context.Response.Headers["Cache-Control"] = "no-store"
});

app.MapGet("/api/boards/{id}", async (string id, HttpContext context) =>
{
    if (!delays.TryGetValue(id, out int delay))
    {
        context.Items["result_status"] = 404;
        return Results.Json(new { code = "NOT_FOUND", message = "Board not found" }, statusCode: 404);
    }
    // The fixture deliberately ignores caller cancellation: the server may finish after the caller gave up.
    if (delay > 0) await Task.Delay(delay);
    context.Items["result_status"] = 200;
    return Results.Text(referenceBoard, "application/json");
});

app.MapGet("/healthz", () => Results.Text("Healthy"));   // narrow liveness only

app.Run();

async Task PushToLoki(string line)
{
    try
    {
        string ns = (DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() * 1_000_000).ToString();
        var payload = new { streams = new[] { new { stream = new { job = Job, session }, values = new[] { new[] { ns, line } } } } };
        using var content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");
        var response = await lokiClient.PostAsync(lokiUrl!.TrimEnd('/') + "/loki/api/v1/push", content);
        if (!response.IsSuccessStatusCode)
            Console.Error.WriteLine($"LOKI_DELIVERY_WARNING status={(int)response.StatusCode}");
    }
    catch (Exception error)
    {
        // A delivery warning means the record's transport failed; the HTTP response was already decided.
        Console.Error.WriteLine($"LOKI_DELIVERY_WARNING {error.GetType().Name}: {error.Message}");
    }
}
