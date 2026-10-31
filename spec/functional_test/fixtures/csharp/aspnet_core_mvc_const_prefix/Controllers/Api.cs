using Microsoft.AspNetCore.Mvc;

public static class Constants
{
    public const string PrefixApi = "/api";
    public const string Unknown = ExternalNames.Prefix;
}

[ApiController]
[Route(Constants.PrefixApi)]
public abstract class ApiBase : Controller
{
}

public sealed class ClientsController : ApiBase
{
    [Route("apps/{app}/clients")]
    public IActionResult GetClients(string app) => Ok();

    [HttpDelete("apps/{app}/clients/{id}")]
    public IActionResult DeleteClient(string app, string id) => Ok();
}

[Route(Constants.Unknown)]
public class OtherController : Controller
{
    [HttpGet("other")]
    public IActionResult Get() => Ok();
}
