using Microsoft.AspNetCore.Mvc;

namespace Shop.Controllers;

// `[Route]` sits above more than five other attributes.
[Route("api/reports")]
[ApiController]
[ApiVersion("1.0")]
[ApiVersion("2.0")]
[Authorize(Policy = "Reports")]
[Produces("application/json")]
[ProducesResponseType(StatusCodes.Status401Unauthorized)]
public class ReportsController : ControllerBase
{
    [HttpGet("{id}")]
    public ActionResult<Report> Get(int id) => Ok();
}

// Every `[Route]` on a controller is a prefix of its actions.
[ApiController]
[Route("api/products")]
[Route("api/v2/products")]
public class ProductsController : ControllerBase
{
    [HttpGet("search")]
    public IActionResult Search([FromQuery] string q) => Ok();

    [HttpGet("~/legacy/products")]
    public IActionResult Legacy() => Ok();
}

// `[Route]` is inherited from a base controller.
[ApiController]
[Route("api/[controller]")]
public abstract class ApiControllerBase : ControllerBase
{
}

public class OrdersController : ApiControllerBase
{
    [HttpGet("{id}")]
    public IActionResult Get(int id) => Ok();
}

// `[area]` takes the `[Area]` name.
[Area("Admin")]
[Route("[area]/[controller]/[action]")]
public class DashboardController : Controller
{
    public IActionResult Index() => View();
}
