using Microsoft.AspNetCore.Mvc;

namespace App.Controllers;

[ApiController]
[Route("api/[controller]")]
public abstract class CrudController<T> : ControllerBase
{
    [HttpGet]
    public virtual IActionResult GetAll([FromQuery] int page) => Ok();

    [HttpGet("{id}")]
    public virtual IActionResult GetOne(int id) => Ok();

    [HttpPost]
    public virtual IActionResult Create([FromBody] T item) => Ok();

    [HttpDelete("{id}")]
    public virtual IActionResult Delete(int id) => Ok();
}

public class WidgetsController : CrudController<Widget>
{
    // override without repeating the attribute: [HttpGet("{id}")] is inherited
    public override IActionResult GetOne(int id) => Ok();

    // override that re-declares
    [HttpDelete("{id}")]
    [Authorize(Roles = "admin")]
    public override IActionResult Delete(int id) => Ok();

    [HttpGet("search")]
    public IActionResult Search(string q) => Ok();
}

public class GadgetsController : CrudController<Gadget> { }

public class Widget { public string Name { get; set; } }
public class Gadget { public string Sku { get; set; } }
