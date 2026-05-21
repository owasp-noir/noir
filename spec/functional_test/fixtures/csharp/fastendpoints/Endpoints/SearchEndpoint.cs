using FastEndpoints;
using MyApp.Requests;

namespace MyApp.Endpoints;

public class SearchEndpoint : Endpoint<SearchRequest>
{
    public override void Configure()
    {
        Get("/search");
        AllowAnonymous();
    }

    public override async Task HandleAsync(SearchRequest req, CancellationToken ct)
    {
        await SendOkAsync();
    }
}
