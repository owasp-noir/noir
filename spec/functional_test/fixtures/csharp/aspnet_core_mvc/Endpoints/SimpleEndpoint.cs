using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using System.Threading.Tasks;

namespace Demo.Endpoints
{
    public class SimpleEndpoint
    {
        public void Register(Microsoft.AspNetCore.Routing.IEndpointRouteBuilder routeBuilder)
        {
            routeBuilder.MapGet("/mapped/health", async context =>
            {
                await context.Response.WriteAsync("ok");
            });

            routeBuilder.MapPost("/mapped/items/{id}", async context =>
            {
                var fromQuery = context.Request.Query["filter"];
                var fromHeader = context.Request.Headers["X-Trace-Id"];
                var fromCookie = context.Request.Cookies["sessionId"];
                await context.Response.WriteAsync("posted");
            });

            routeBuilder.MapMethods("/mapped/methods", new[] { "PUT", "DELETE" }, context =>
            {
                return Task.CompletedTask;
            });

            routeBuilder.MapGet("/mapped/rich", async context =>
            {
                var query = context.Request.Query["q"];
                var header = context.Request.Headers["X-Test"];
                var cookie = context.Request.Cookies["cid"];
                await context.Response.WriteAsync($"{query}-{header}-{cookie}");
            });

            routeBuilder.MapPost("/mapped/form", async context =>
            {
                var form = context.Request.Form["name"];
                await context.Response.WriteAsync(form);
            });
        }
    }
}
