var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

// The Microsoft docs shape: one extension method, mounted under two groups.
app.MapGroup("/public/todos")
    .MapTodosApi()
    .WithTags("Public");

app.MapGroup("/private/todos")
    .MapTodosApi()
    .WithTags("Private")
    .RequireAuthorization();

var api = app.MapGroup("/api");
api.MapGroup("/v1").MapAdminApi();

app.Run();
