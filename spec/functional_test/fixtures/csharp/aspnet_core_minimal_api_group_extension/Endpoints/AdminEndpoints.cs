public static class AdminEndpoints
{
    // Called from Program.cs on `api.MapGroup("/v1")`; nests another group
    // extension under its own sub-group.
    public static IEndpointRouteBuilder MapAdminApi(this RouteGroupBuilder group)
    {
        group.MapGet("/admin/stats", () => Results.Ok());
        group.MapGroup("/admin").MapUsersApi();
        return group;
    }

    public static RouteGroupBuilder MapUsersApi(this RouteGroupBuilder users)
    {
        users.MapDelete("/users/{id}", (int id) => Results.NoContent());
        return users;
    }
}
