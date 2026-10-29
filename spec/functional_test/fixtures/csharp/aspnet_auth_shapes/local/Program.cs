var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

var rules = app.MapGroup("/rules").RequireAuthorization("Member");
rules.MapGet("", () => Results.Ok());
rules.MapPost("/", () => Results.Ok());
rules.MapDelete("{id}",
    async (string id) =>
    {
        await Task.Delay(1);
        return Results.NoContent();
    })
    .AllowAnonymous();

var notes = app.MapGroup("/notes");
notes.RequireAuthorization("Member");
notes.MapPost("/", () => Results.Ok());

app.Run();
