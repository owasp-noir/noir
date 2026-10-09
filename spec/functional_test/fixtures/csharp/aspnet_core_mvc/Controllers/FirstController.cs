using Microsoft.AspNetCore.Mvc;

namespace Demo.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class FirstController : ControllerBase
    {
        // Attribute and action on one line: the attribute's own parens must
        // not be read as the parameter list.
        [HttpGet("b")] public IActionResult B1(int k, string z) { return Ok(); }

        [HttpGet][Authorize(Roles = "Admin")] public IActionResult C1(int k) { return Ok(); }

        // `~/` is app-rooted: it overrides the controller's [Route] prefix.
        [HttpGet("~/first/health")]
        public IActionResult Health() { return Ok(); }
    }

    [Route("~/rooted/[controller]")]
    public class TildeController : ControllerBase
    {
        [HttpGet("x")]
        public IActionResult X() { return Ok(); }
    }
}
