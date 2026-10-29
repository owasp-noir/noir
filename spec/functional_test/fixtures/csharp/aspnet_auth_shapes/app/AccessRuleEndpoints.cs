using Microsoft.AspNetCore.Mvc;

public static class AccessRuleEndpoints
{
    public static RouteGroupBuilder MapAccessRuleEndpoints(this RouteGroupBuilder group)
    {
        group.RequireAuthorization("Member");
        group.MapGet("", ([FromRoute] Guid orgId) => Results.Ok(orgId));
        group.MapGet("{id:guid}", ([FromRoute] Guid orgId, Guid id) => Results.Ok(id));
        group.MapPut("{id:guid}", ([FromRoute] Guid orgId, Guid id) => Results.Ok(id)).RequireAuthorization("ManageRules");
        group.MapDelete("{id:guid}",
            async ([FromRoute] Guid orgId, Guid id) =>
            {
                await Task.Delay(1);
                return Results.NoContent();
            })
            .RequireAuthorization("ManageRules");
        return group;
    }

    // No access modifier. The guarded method above must not cover this one.
    RouteGroupBuilder MapHealthEndpoints(this RouteGroupBuilder group)
    {
        group.MapGet("/healthz", () => Results.Ok());
        return group;
    }

    // Another method's `group` is not the one above: its routes stay open.
    public static RouteGroupBuilder MapPublicEndpoints(this RouteGroupBuilder group)
    {
        group.MapGet("/status", () => Results.Ok());
        return group;
    }
}
