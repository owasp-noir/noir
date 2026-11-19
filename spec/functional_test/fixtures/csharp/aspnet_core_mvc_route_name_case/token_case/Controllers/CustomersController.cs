using Microsoft.AspNetCore.Mvc;

namespace App.Controllers;

// Token names are looked up in a case-insensitive route-value dictionary,
// so [Controller] / [Action] / [Area] are the same tokens as the lowercase ones.
[ApiController]
[Route("api/[Controller]")]
public class CustomersController : ControllerBase
{
    [HttpGet]
    public IActionResult GetAll() => Ok();

    [HttpGet("{id}")]
    public IActionResult Get(int id) => Ok();

    [HttpPost("[Action]")]
    public IActionResult Import() => Ok();
}

[Area("Admin")]
[Route("[Area]/[Controller]/[Action]")]
public class AuditController : Controller
{
    public IActionResult Index() => View();
}

// Control
[ApiController]
[Route("api/[controller]")]
public class OrdersController : ControllerBase
{
    [HttpGet("[action]")]
    public IActionResult Recent() => Ok();
}
