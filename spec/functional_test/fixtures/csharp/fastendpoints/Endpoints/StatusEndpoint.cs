using FastEndpoints;

namespace MyApp.Endpoints;

public record StatusResponse(string Health);

// Response-only endpoint — generic arg is the response, NOT a request DTO.
// If misread as a request, properties on `StatusResponse` (e.g. `Health`)
// would leak onto the endpoint params.
public class StatusEndpoint : EndpointWithoutRequest<StatusResponse>
{
    public override void Configure()
    {
        Get("/status");
        AllowAnonymous();
        // Get("/decoy") — commented out, must not surface as an endpoint
    }

    public override async Task HandleAsync(CancellationToken ct)
    {
        await SendAsync(new StatusResponse("ok"));
    }
}
