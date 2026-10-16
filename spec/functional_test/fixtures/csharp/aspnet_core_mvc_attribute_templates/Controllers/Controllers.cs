using Microsoft.AspNetCore.Mvc;

namespace Shop.Controllers;

// A string literal inside a sibling attribute is not a route template, and
// `[ActionName]` renames the action in the conventional route.
public class LogController : Controller
{
    [HttpGet]
    public IActionResult List() => View();

    [HttpPost, ActionName("List")]
    public IActionResult ListPost(string q) => View();

    [HttpPost, ParameterBasedOnFormName("save-continue", "continueEditing")]
    public IActionResult Edit() => View();

    [HttpGet, Authorize("Admin")]
    public IActionResult Secure() => View();

    [HttpGet, Produces("application/json")]
    public IActionResult Feed() => View();

    [HttpGet][Authorize("Admin")]
    public IActionResult Stacked() => View();
}

[Route("api/items")]
public class ItemsController : ControllerBase
{
    // The verb attribute has no literal; the Route on the same line routes it.
    [HttpDelete, EnableRateLimiting("fixed"), Route("rm")]
    public IActionResult Remove() => Ok();

    // A constant route argument cannot be read: the action is skipped rather
    // than reported at the class route.
    [HttpGet(ApiRoutes.Items.Get)]
    public IActionResult Get() => Ok();

    [HttpPost(Const.Prefix + "/create")]
    public IActionResult Create() => Ok();

    // Named-only and empty arguments are not unresolved: class route.
    [HttpGet(Name = "ListItems")]
    public IActionResult All() => Ok();

    [HttpPut("")]
    public IActionResult Replace() => Ok();

    [HttpGet("{id}", Name = "GetItem")]
    public IActionResult One(int id) => Ok();
}
