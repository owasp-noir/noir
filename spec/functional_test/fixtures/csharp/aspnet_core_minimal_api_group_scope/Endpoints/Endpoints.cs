using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Routing;

namespace App.Endpoints;

public static class Endpoints
{
    public static void MapUserEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/users");
        group.MapGet("/", () => "list users");
        group.MapGet("/{id:int}", (int id) => "get user");
    }

    public static void MapOrderEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/orders");
        group.MapGet("/", () => "list orders");
        group.MapPost("/", () => "create order");
    }

    public static RouteGroupBuilder MapProductsApi(this RouteGroupBuilder group)
    {
        group.MapGet("/", () => "list products");
        group.MapDelete("/{id:int}", (int id) => "delete product");
        return group;
    }
}
