using Microsoft.AspNetCore.Mvc;

namespace Fx.A
{
    [ApiRoute("users")]
    public class UsersController : Controller
    {
        [HttpGet]
        public IActionResult Index() => Ok();
    }
}
