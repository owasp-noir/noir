using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.DependencyInjection;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddControllersWithViews();

var app = builder.Build();

// Only ServiceA's controllers answer on this template.
app.MapControllerRoute(
    name: "service-a",
    pattern: "a/{controller}/{action}");

app.MapControllers();
app.Run();
