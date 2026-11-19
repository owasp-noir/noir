using Microsoft.AspNetCore.Mvc;

namespace App.Controllers;

// ASP.NET Core 3.0+ trims the "Async" suffix from action names
// (MvcOptions.SuppressAsyncSuffixInActionNames defaults to true), for
// conventional routes and for the [action] token alike.
[Route("api/[controller]/[action]")]
public class UsersController : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> GetUsersAsync() => Ok();

    [HttpPost]
    public async Task<IActionResult> CreateUserAsync([FromBody] string name) => Ok();

    // Control: [ActionName] wins and is already honoured.
    [HttpGet, ActionName("Lookup")]
    public async Task<IActionResult> FindAsync(string q) => Ok();
}

public class OrdersController : Controller
{
    public async Task<IActionResult> ListAsync() => View();
    public async Task<IActionResult> DetailsAsync(int id) => View();
    public IActionResult Index() => View();
}
