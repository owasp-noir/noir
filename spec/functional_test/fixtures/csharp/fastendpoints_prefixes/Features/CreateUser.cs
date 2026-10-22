using FastEndpoints;

namespace App.Features;

public class CreateUserRequest
{
    public string FirstName { get; set; }
    [BindFrom("last_name")]
    public string LastName { get; set; }
    [QueryParam]
    public bool Notify { get; set; }
    [FromHeader("X-Tenant")]
    public string Tenant { get; set; }
    [BindFrom("nick")] public string NickName { get; set; }
}

public class CreateUserEndpoint : Endpoint<CreateUserRequest, UserResponse>
{
    public override void Configure()
    {
        Post("/users/{GroupId}", "/members/{GroupId}");
        Version(1);
        AllowAnonymous();
    }

    public override async Task HandleAsync(CreateUserRequest req, CancellationToken ct)
    {
        await SendAsync(new UserResponse());
    }
}

public class GetUserEndpoint : EndpointWithoutRequest
{
    public override void Configure()
    {
        Verbs(Http.GET, Http.HEAD);
        Routes("/users/{id}");
        Group<AdminGroup>();
    }

    public override async Task HandleAsync(CancellationToken ct)
    {
        var id = Route<int>("id");
        var q = Query<string>("q", isRequired: false);
        await SendOkAsync(ct);
    }
}

public class HealthEndpoint : EndpointWithoutRequest
{
    public override void Configure()
    {
        Get("/health");
        RoutePrefixOverride("internal");
        Group<AuditGroup>();
    }

    public override async Task HandleAsync(CancellationToken ct) => await SendOkAsync(ct);
}

public sealed class AdminGroup : Group
{
    public AdminGroup()
    {
        Configure("admin", ep => ep.Description(x => x.WithTags("admin")));
    }
}

public sealed class AuditGroup : SubGroup<AdminGroup>
{
    public AuditGroup()
    {
        Configure("audit", ep => { });
    }
}
