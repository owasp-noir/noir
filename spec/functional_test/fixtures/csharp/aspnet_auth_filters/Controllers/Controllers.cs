using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using App.Filters;

namespace App.Controllers;

[RequireAdmin]
[StoreClosed]
public abstract class BaseAdminController : Controller
{
}

public class ReportsController : BaseAdminController
{
    public IActionResult Index()
    {
        return View();
    }

    [RequireAdmin(ignore: true)]
    public IActionResult Status()
    {
        return Ok();
    }
}

[Authorize]
public abstract class SecureBase : Controller
{
}

public class SettingsController : SecureBase
{
    public IActionResult Index()
    {
        return View();
    }
}

[StoreClosed]
public class AccountController : Controller
{
    [SignedIn]
    public IActionResult Profile()
    {
        return View();
    }

    [HttpPost]
    public IActionResult Login(string username, string password)
    {
        if (!_signInManager.PasswordSignIn(username, password))
            return Unauthorized();

        return Redirect("/");
    }

    public async Task<IActionResult> Orders()
    {
        var user = await _userManager.GetUserAsync(User);
        if (user == null)
            return Challenge();

        return View();
    }

    public async Task<IActionResult> Quote(int id)
    {
        var result = await CheckCallerAsync();
        if (result != null)
            return result;

        return View();
    }

    private async Task<IActionResult> CheckCallerAsync()
    {
        if (!User.Identity.IsAuthenticated)
            return Forbid();

        return null;
    }

    // Refuses one named user: anonymous passes.
    public IActionResult Named()
    {
        if (User.Identity.Name == "banned") return Forbid();
        return Ok();
    }

    // A lookup by input, not the caller.
    public async Task<IActionResult> Lookup(int id)
    {
        var user = await _userService.GetUserAsync(id);
        if (user == null) return Unauthorized();
        return Ok(user);
    }

    // A body property named User.
    public IActionResult Token(TokenRequest request)
    {
        if (request.User == null) return Unauthorized();
        return Ok();
    }

    // Not the owner: an anonymous caller never is.
    public async Task<IActionResult> Invoice(int orderId)
    {
        var order = await _orderService.GetOrderByIdAsync(orderId);
        var customer = await _workContext.GetCurrentCustomerAsync();
        if (order == null || customer.Id != order.CustomerId)
            return Challenge();
        return Ok();
    }
}

public class ItemsController : Controller
{
    [AjaxOnly]
    public IActionResult Ajax() => Ok();

    [RequireLogin(true)]
    public IActionResult Strict() => Ok();

    // `[AllowAnonymous]` does not lift a filter that never reads it.
    [AllowAnonymous]
    [RequireLogin]
    public IActionResult Anon() => Ok();
}
