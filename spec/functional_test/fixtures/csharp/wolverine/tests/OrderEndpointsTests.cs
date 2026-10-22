using Wolverine.Http;

public static class FakeEndpoints
{
    [WolverineGet("/test-only")]
    public static string Get() => "test";
}
