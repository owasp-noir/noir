using Microsoft.AspNetCore.Mvc;
using Alpha.Web;

namespace App.Controllers;

public class UsersController : ApiController
{
    [HttpGet("users")]
    public IActionResult List() => Ok();

    [Route("users/search")]
    public IActionResult Search() => Ok();
}
