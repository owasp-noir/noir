using FastEndpoints;
using MyApp.Requests;

namespace MyApp.Endpoints;

public class DeleteUserEndpoint : Endpoint<DeleteUserRequest>
{
    public override void Configure()
    {
        Delete("/users/{Id}");
        Roles("admin");
    }

    public override async Task HandleAsync(DeleteUserRequest req, CancellationToken ct)
    {
        await SendNoContentAsync();
    }
}
