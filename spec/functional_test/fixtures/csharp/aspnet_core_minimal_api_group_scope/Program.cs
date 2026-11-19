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

app.Run();
