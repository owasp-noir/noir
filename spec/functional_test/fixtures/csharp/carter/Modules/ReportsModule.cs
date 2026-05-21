using Carter;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Routing;
using System.Threading.Tasks;

namespace CarterDemo.Modules
{
    public class ReportsModule : ICarterModule
    {
        public void AddRoutes(IEndpointRouteBuilder app)
        {
            var group = app.MapGroup("/api/reports");

            group.MapGet("/", async context =>
            {
                var trace = context.Request.Headers["X-Trace-Id"];
                await context.Response.WriteAsync($"{trace}");
            });

            group.MapGet("/{id}", async context =>
            {
                var session = context.Request.Cookies["sid"];
                await context.Response.WriteAsync($"{session}");
            });

            group.MapMethods("/bulk", new[] { "PATCH", "POST" }, async context =>
            {
                var form = context.Request.Form["payload"];
                await context.Response.WriteAsync(form);
            });

            app.MapGroup("/admin").MapPost("/notify", async context =>
            {
                var subject = context.Request.Form["subject"];
                await context.Response.WriteAsync(subject);
            });
        }
    }
}
