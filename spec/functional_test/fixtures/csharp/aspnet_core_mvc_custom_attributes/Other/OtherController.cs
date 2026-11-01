using Fx.Http;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Fx.Other
{
    // Its project is not referenced by the host that sets the FallbackPolicy.
    [Route("other")]
    public class OtherController : Controller
    {
        [HttpGet]
        public IActionResult Index()
        {
            return Ok();
        }
    }

    // The inherited actions answer to the controller that owns them, not to
    // the base class they are written in.
    [Route("secure")]
    [Authorize]
    public class SecureController : RestController<Dummy>
    {
    }

    [Route("open")]
    public class OpenController : RestController<Dummy>
    {
    }

    // The controller's own in-body refusal guards its own action only.
    [Route("refusing")]
    public class RefusingController : RestController<Dummy>
    {
        [HttpGet("me")]
        public IActionResult Me()
        {
            if (!User.Identity.IsAuthenticated)
            {
                return Unauthorized();
            }
            return Ok();
        }
    }

    public class Dummy
    {
    }
}
