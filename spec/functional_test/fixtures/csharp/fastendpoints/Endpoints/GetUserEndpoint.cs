using FastEndpoints;
using MyApp.Requests;

namespace MyApp.Endpoints;

public class GetUserEndpoint : Endpoint<GetUserRequest>
{
    public override void Configure()
    {
        Get("/users/{Id}");
        AllowAnonymous();
    }

    public override async Task HandleAsync(GetUserRequest req, CancellationToken ct)
    {
        await SendAsync(new { id = req.Id });
    }
}
