using Microsoft.AspNetCore.Authorization;

var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

// M1: lambda with braces in strings
app.MapGet("/m1", () => "{ not a block }");

// M2: [Authorize] lambda
app.MapGet("/m2", [Authorize] () => Results.Ok());

// M3: commented-out route
// app.MapPost("/ghost", () => 1);

// M4: chained auth after block-lambda containing "}" strings
app.MapPost("/m4", (Item item) =>
{
    var s = "})";
    return Results.Ok(s);
}).RequireAuthorization();

// M5: method group handler with attributes
app.MapGet("/m5/{id}", Handlers.GetItem);

// M6: a route mapped inside a one-line [Authorize] method is not its handler
Routes.Map(app);

app.Run();

static class Handlers
{
    [Authorize]
    public static IResult GetItem(int id, [FromQuery(Name = "v")] string? version) => Results.Ok();
}

static class Routes
{
    [Authorize] public static void Map(WebApplication app) { app.MapGet("/m6", () => 1); }
}

record Item(string Name);
