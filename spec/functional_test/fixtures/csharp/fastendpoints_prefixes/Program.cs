using FastEndpoints;
var bld = WebApplication.CreateBuilder();
bld.Services.AddFastEndpoints();
var app = bld.Build();
app.UseFastEndpoints(c => { c.Endpoints.RoutePrefix = "api"; });
app.Run();
