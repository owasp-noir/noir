using FastEndpoints;
using MyApp.Requests;

namespace MyApp.Endpoints;

public class CreateUserEndpoint : Endpoint<CreateUserRequest>
{
    public override void Configure()
    {
        Post("/users");
        Roles("admin");
    }

    public override async Task HandleAsync(CreateUserRequest req, CancellationToken ct)
    {
        await SendOkAsync();
    }
}
