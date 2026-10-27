using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace App.Admin;

// Same name as App.Public's: its [AllowAnonymous] must not reach here.
public abstract partial class BaseApiController : ControllerBase
{
}

[Authorize(Roles = "Admin")]
[Route("api/admin/users")]
public class UsersController : BaseApiController
{
    [HttpGet]
    public IActionResult List() => Ok();
}
