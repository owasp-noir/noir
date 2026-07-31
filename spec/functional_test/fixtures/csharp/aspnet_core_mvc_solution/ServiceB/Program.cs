using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.DependencyInjection;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddControllersWithViews();

var app = builder.Build();

// Only ServiceB's controllers answer on this template.
app.MapControllerRoute(
    name: "service-b",
    pattern: "b/{controller}/{action}/{id?}");

app.MapControllers();
app.Run();
