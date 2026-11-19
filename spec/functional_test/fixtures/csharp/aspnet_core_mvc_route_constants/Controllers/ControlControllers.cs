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
