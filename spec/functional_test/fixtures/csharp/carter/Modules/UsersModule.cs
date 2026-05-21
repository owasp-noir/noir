using Carter;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Routing;
using System.Threading.Tasks;

namespace CarterDemo.Modules
{
    public class UsersModule : ICarterModule
    {
        public void AddRoutes(IEndpointRouteBuilder app)
        {
            app.MapGet("/users", () => "list");

            app.MapPost("/users", async context =>
            {
                using var doc = await System.Text.Json.JsonDocument.ParseAsync(context.Request.Body);
                var root = doc.RootElement;
                var name = root.GetProperty("name").GetString();
                await context.Response.WriteAsync(name ?? "");
            });

            app.MapGet("/users/{id}", async context =>
            {
                var filter = context.Request.Query["filter"];
                await context.Response.WriteAsync($"{filter}");
            });

            app.MapPut("/users/{id}", async context =>
            {
                using var doc = await System.Text.Json.JsonDocument.ParseAsync(context.Request.Body);
                var name = doc.RootElement.GetProperty("name").GetString();
                await context.Response.WriteAsync(name ?? "");
            });

            app.MapDelete("/users/{id}", async context =>
            {
                var soft = context.Request.Query["soft"];
                await context.Response.WriteAsync($"{soft}");
            });
        }
    }
}
