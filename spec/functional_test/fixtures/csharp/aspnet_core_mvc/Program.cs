using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;
using System.Threading.Tasks;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllersWithViews();

var app = builder.Build();

app.MapControllerRoute(
    name: "api-v2",
    pattern: "api/v2/{controller=Home}/{action=Index}/{id?}");

app.MapControllerRoute(
    name: "default",
    pattern: "{controller=Home}/{action=Index}/{id?}");

var api = app.MapGroup("/api");
var v1 = api.MapGroup("/v1");

v1.MapGet("/grouped/{id}", async context =>
{
    var mode = context.Request.Query["mode"];
    await context.Response.WriteAsync($"{mode}");
});

api.MapMethods("/bulk", new[] { "PATCH", "POST" }, context =>
{
    return Task.CompletedTask;
});

app.MapGroup("/chained").MapPost("/submit", async context =>
{
    var trace = context.Request.Headers["X-Trace"];
    await context.Response.WriteAsync($"{trace}");
});

app.MapControllers();
app.Run();
