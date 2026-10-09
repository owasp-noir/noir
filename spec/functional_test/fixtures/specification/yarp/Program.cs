using Yarp.ReverseProxy.Configuration;

var builder = WebApplication.CreateBuilder(args);

var routes = new[]
{
    new RouteConfig
    {
        RouteId = "admin",
        ClusterId = "admin-cluster",
        Match = new RouteMatch
        {
            Path = "/admin/{*rest}",
            Methods = new[] { "DELETE" }
        }
    },
    new RouteConfig
    {
        RouteId = "reports",
        ClusterId = "reports-cluster",
        Match = new() { Path = "/reports" },
    },
    new RouteConfig
    {
        RouteId = "status",
        ClusterId = "status-cluster",
        Match = new RouteMatch { Path = "/status/{name?}", Methods = ["PATCH"] },
    },
};

builder.Services.AddReverseProxy()
    .LoadFromMemory(routes, clusters)
    .LoadFromConfig(builder.Configuration.GetSection("ReverseProxy"));

var app = builder.Build();
app.MapReverseProxy();
app.Run();
