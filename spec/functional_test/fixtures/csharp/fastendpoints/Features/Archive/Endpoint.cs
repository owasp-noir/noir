using FastEndpoints;

namespace MyApp.Features.Archive;

// A feature-local request DTO whose name collides with other feature folders'
// DTOs. Resolution must stay inside this file, not union every same-named type
// in the solution.
public class Request
{
    public string ArchiveId { get; set; } = string.Empty;
}

public class Endpoint : Endpoint<Request>
{
    public override void Configure()
    {
        Post("/archive");
        AllowAnonymous();
    }
}
