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
                await context.Response.WriteAsync("posted");
            });

            routeBuilder.MapMethods("/mapped/methods", new[] { "PUT", "DELETE" }, context =>
            {
                return Task.CompletedTask;
            });
        }
    }
}
