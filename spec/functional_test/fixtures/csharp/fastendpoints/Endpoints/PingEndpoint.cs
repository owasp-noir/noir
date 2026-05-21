using FastEndpoints;

namespace MyApp.Endpoints;

public class PingEndpoint : EndpointWithoutRequest
{
    public override void Configure()
    {
        Get("/ping");
        AllowAnonymous();
    }

    public override async Task HandleAsync(CancellationToken ct)
    {
        await SendStringAsync("pong");
    }
}
