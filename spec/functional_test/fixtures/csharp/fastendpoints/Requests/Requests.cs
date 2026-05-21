using FastEndpoints;

namespace MyApp.Requests;

public class GetUserRequest
{
    [FromRoute]
    public int Id { get; set; }
}

public class CreateUserRequest
{
    public string Name { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
}

public class SearchRequest
{
    [FromQuery]
    public string? Keyword { get; set; }

    [FromQuery]
    public int Page { get; set; }

    [FromHeader("X-Trace-Id")]
    public string? TraceId { get; set; }
}

public record DeleteUserRequest(int Id, bool Soft);
