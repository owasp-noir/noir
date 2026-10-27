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
}
