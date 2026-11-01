using Fx.Http;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Fx.Api
{
    [V3ApiController("ping")]
    [AllowAnonymous]
    public class PingController : Controller
    {
        [HttpGet]
        public IActionResult Status()
        {
            return Ok();
        }
    }
}
