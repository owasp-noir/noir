using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Shapes.Controllers;

// P1: generic base with attributed actions, inherited by a routed controller
public abstract class CrudController<T> : ControllerBase where T : class, new()
{
    [HttpGet("{id}")]
    public virtual IActionResult GetOne(int id) => Ok();

    [HttpDelete("{id}")]
    public IActionResult DeleteOne(int id) => Ok();
}

[Authorize]
[Route("api/items")]
public class ItemsController : CrudController<Item>
{
    [HttpGet]
    public IActionResult All() => Ok();
}

public class Item { }

// P2: partial controller split across declarations
[Route("api/split")]
public partial class SplitController : ControllerBase { }

public partial class SplitController
{
    [HttpGet("one")]
    public IActionResult One() => Ok();
}
