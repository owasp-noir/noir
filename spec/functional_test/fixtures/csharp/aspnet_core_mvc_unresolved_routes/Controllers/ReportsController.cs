using Microsoft.AspNetCore.Mvc;

namespace Shop.Controllers;

// Every action routes through a constant (`ApiRoutes.Reports.*`): the template
// cannot be read, but the controller and its verbs are real. They are reported
// at the class route and tagged `unresolved-route`, never silently dropped.
[ApiController]
[Route("api/[controller]")]
public class ReportsController : ControllerBase
{
    [HttpGet(ApiRoutes.Reports.List)]
    public IActionResult List() => Ok();

    [HttpPost(Const.Prefix + "/create")]
    public IActionResult Create() => Ok();

    // The literal in the sibling attribute is not the route.
    [HttpDelete(nameof(Remove)), Authorize("Admin")]
    public IActionResult Remove() => Ok();

    // A readable literal is untouched.
    [HttpGet("{id}")]
    public IActionResult One(int id) => Ok();
}
