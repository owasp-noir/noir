using Wolverine;
using Wolverine.Http;

var builder = WebApplication.CreateBuilder(args);
builder.Host.UseWolverine();
builder.Services.AddWolverineHttp();

var app = builder.Build();
app.MapWolverineEndpoints();
app.Run();
