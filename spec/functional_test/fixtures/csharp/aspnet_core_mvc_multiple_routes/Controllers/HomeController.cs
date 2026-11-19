using Microsoft.AspNetCore.Mvc;

namespace App.Controllers;

// Verbatim shape of "Routing to controller actions in ASP.NET Core" >
// "Multiple attribute routes".
public class HomeController : Controller
{
    [Route("")]
    [Route("Home")]
    [Route("Home/Index")]
    [Route("Home/Index/{id?}")]
    public IActionResult Index(int? id) => View();

    [Route("Home/About")]
    [Route("Home/About/{id?}")]
    public IActionResult About(int? id) => View();
}

[ApiController]
[Route("api/reports")]
public class ReportsController : ControllerBase
{
    // One verb, two templates.
    [HttpGet]
    [Route("latest")]
    [Route("current")]
    public IActionResult Latest() => Ok();

    // [Route] and a templated [HttpGet] are two selectors: ANY archive, GET history.
    [Route("archive")]
    [HttpGet("history")]
    public IActionResult Archive() => Ok();

    // Control: several templated verb attributes already work.
    [HttpPost("run")]
    [HttpPost("execute")]
    public IActionResult Run() => Ok();
}
