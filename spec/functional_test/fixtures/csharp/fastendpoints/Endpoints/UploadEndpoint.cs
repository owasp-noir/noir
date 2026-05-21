using FastEndpoints;

namespace MyApp.Endpoints;

public class UploadRequest
{
    [FromBody]
    public string Payload { get; set; } = string.Empty;

    [FromCookie]
    public string SessionId { get; set; } = string.Empty;
}

public class UploadEndpoint : Endpoint<UploadRequest>
{
    public override void Configure()
    {
        Post("/uploads");
        Permissions("uploads:write");
    }

    public override async Task HandleAsync(UploadRequest req, CancellationToken ct)
    {
        await SendOkAsync();
    }
}
