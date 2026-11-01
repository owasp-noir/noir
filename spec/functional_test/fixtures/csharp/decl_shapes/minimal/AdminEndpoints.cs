using Microsoft.AspNetCore.Authorization;

namespace Shapes.Minimal;

// M7: attributes of the class declaring minimal API routes do not apply to them
[AllowAnonymous]
public static class AdminEndpoints
{
    public static void MapAdmin(this WebApplication app)
    {
        app.MapGet("/admin/users", () => "x").RequireAuthorization("Admin");
        app.MapDelete("/admin/users/{id}", [Authorize] (int id) => id);
        var g = app.MapGroup("/admin/g").RequireAuthorization();
        g.MapPost("/wipe", () => "x");
    }
}

[Authorize]
public static class UserEndpoints
{
    public static void MapUsers(this WebApplication app)
    {
        app.MapGet("/users", () => "x");
    }
}
