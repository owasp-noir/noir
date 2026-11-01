using FastEndpoints;

namespace Shapes.Fe;

public class CreateUserRequest
{
    // F1: attribute split over lines
    [FromHeader(
        "X-Tenant")]
    public string Tenant { get; set; }

    // F2: attribute with a bracket in a string
    [BindFrom("a]b")]
    public string Weird { get; set; }

    [QueryParam] public int Page { get; set; }

    public string Name { get; set; }
}

public class CreateUserEndpoint : Endpoint<CreateUserRequest>
{
    public override void Configure()
    {
        Post("/users");
        AllowAnonymous();
    }

    public override async Task HandleAsync(CreateUserRequest req, CancellationToken ct)
    {
        await SendOkAsync(ct);
    }
}
