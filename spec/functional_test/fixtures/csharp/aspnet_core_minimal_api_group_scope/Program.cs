using Microsoft.AspNetCore.Builder;

var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

app.MapUserEndpoints();
app.MapOrderEndpoints();
app.MapGroup("/api/v1/products").MapProductsApi();

// A local function sees the top-level statements' group.
var shared = app.MapGroup("/shared");
MapShared();

void MapShared()
{
    shared.MapGet("/ping", () => "pong");
}

var dynamicGroup = app.MapGroup(builder.Configuration["Group"]);
dynamicGroup.MapGet("/summary", () => "summary");
shared.MapGet("/report" + builder.Configuration["Suffix"], () => "report");

app.MapGet("/selection", First.Status);

app.Run();

class First
{
    public static string Status() => "first";
}

class Second
{
    public static string Status() => "second";
}
