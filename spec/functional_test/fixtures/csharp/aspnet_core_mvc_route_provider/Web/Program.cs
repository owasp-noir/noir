var builder = WebApplication.CreateBuilder(args);
builder.Services.AddControllersWithViews();

var app = builder.Build();
app.UseRouting();
// The route providers register every conventional route.
app.UseEndpoints(endpoints => RouteRegistrar.RegisterAll(endpoints));
app.Run();
