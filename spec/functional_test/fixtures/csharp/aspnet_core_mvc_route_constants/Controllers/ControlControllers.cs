using App.Contracts;
using Microsoft.AspNetCore.Mvc;

namespace App.Controllers;

// Class-level [Route(<constant>)]: what is and is not read today.
[Route(ApiRoutes.Health)]
public class HealthController : ControllerBase
{
    [HttpGet]
    public IActionResult Get() => Ok();
}

[Route(ApiRoutes.Interp)]
public class InterpController : ControllerBase
{
    [HttpGet]
    public IActionResult Get() => Ok();
}

[Route(ApiRoutes.Concat)]
public class ConcatController : ControllerBase
{
    [HttpGet]
    public IActionResult Get() => Ok();
}

// No controller route and a constant the scan does not declare: reported
// conventionally, tagged.
public class LegacyController : Controller
{
    [HttpGet(MissingRoutes.Find)]
    public IActionResult Find() => Ok();

    [Route(MissingRoutes.Index)]
    public IActionResult Index() => View();
}

// A controller route the scan can read only in part (`PayjoinClient` and
// `ExternalRoutes` come from a package): it keeps its readable parts, the
// rest becomes a placeholder, tagged. It is never the site root.
[Route("{cryptoCode}/" + PayjoinClient.BIP21EndpointKey)]
public class PayJoinEndpointController : ControllerBase
{
    [HttpPost("")]
    public IActionResult Submit(string cryptoCode) => Ok();
}

[Route(ExternalRoutes.Base)]
public class ExternalController : ControllerBase
{
    [HttpGet("status")]
    public IActionResult Status() => Ok();

    [HttpGet("/external/ping")]
    public IActionResult Ping() => Ok();
}
