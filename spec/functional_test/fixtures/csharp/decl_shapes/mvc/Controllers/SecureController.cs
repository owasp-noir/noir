using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Shapes.Controllers
{
    // A1: [Authorize] above a long attribute stack
    [Authorize]
    [ApiController]
    [Route("api/secure")]
    [Produces("application/json")]
    [ProducesResponseType(401)]
    [ProducesResponseType(403)]
    [ApiExplorerSettings(GroupName = "v1")]
    public class SecureController : ControllerBase
    {
        [HttpGet("a")]
        public IActionResult A() => Ok();

        // A2: [AllowAnonymous] with a trailing comment ending in ';'
        [AllowAnonymous] // anyone may call;
        [HttpGet("open")]
        public IActionResult Open() => Ok();

        // A3: string mentioning "class X :" inside a method
        [HttpGet("b")]
        public IActionResult B() { var t = "class Fake : Base {"; return Ok(t); }

        [HttpGet("c")]
        public IActionResult C() => Ok();
    }

    // A4: #if splits the attribute stack
    [Authorize]
#if DEBUG
    [ApiExplorerSettings(IgnoreApi = false)]
#endif
    [Route("api/cond")]
    public class CondController : ControllerBase
    {
        [HttpGet("x")]
        public IActionResult X() => Ok();
    }

    [Route("api/plain")]
    public class PlainController : ControllerBase
    {
        // A5: [Authorize] with a trailing comment ending in ';'
        [Authorize] // admins only;
        [HttpGet("admin")]
        public IActionResult Admin() => Ok();

        /* A6: a commented-out [Authorize]
        [Authorize]
        */
        [HttpGet("free")]
        public IActionResult Free() => Ok();

        // A7: [Authorize] attribute split over lines
        [Authorize(
            Roles = "Admin")]
        [HttpGet("roles")]
        public IActionResult Roles() => Ok();

        [HttpGet("after-roles")]
        public IActionResult AfterRoles() => Ok();
    }

    // A8: class header split over lines with attribute on same line as class
    [Route("api/inline")] [Authorize] public class InlineController
        : ControllerBase
    {
        [HttpGet("y")]
        public IActionResult Y() => Ok();
    }
}

namespace Shapes.Controllers
{
    // A9: methods after a nested class still belong to the outer controller
    [Authorize]
    [Route("api/outer")]
    public class OuterController : ControllerBase
    {
        public class Payload
        {
            public int X { get; set; }
        }

        [HttpGet("after-nested")]
        public IActionResult AfterNested() => Ok();
    }
}
