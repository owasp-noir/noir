using FastEndpoints;

namespace MyApp.Endpoints;

public class MultiRouteEndpoint : EndpointWithoutRequest
{
    public override void Configure()
    {
        Verbs(Http.GET, Http.HEAD);
        Routes("/legacy/status", "/v2/status");
        AllowAnonymous();
    }

    public override async Task HandleAsync(CancellationToken ct)
    {
        await SendOkAsync();
    }
}
