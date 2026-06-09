using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.DependencyInjection;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddControllers();
var app = builder.Build();
app.MapControllerRoute(
    name: "default",
    pattern: "a/{controller=Home}/{action=Index}/{id?}");
app.Run();
