using FastEndpoints;

namespace MyApp.Features.Restore;

public class Request
{
    public string RestoreToken { get; set; } = string.Empty;
}

public class Endpoint : Endpoint<Request>
{
    public override void Configure()
    {
        Post("/restore");
        AllowAnonymous();
    }
}
