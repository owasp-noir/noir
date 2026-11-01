using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Shapes.Controllers;

// S15: #if/#else each open the method's brace
[Authorize]
[ApiController]
[Route("api/pp")]
public class PpController : ControllerBase
{
    [HttpGet("one")]
#if DEBUG
    public IActionResult One(int a) {
#else
    public IActionResult One() {
#endif
        return Ok();
    }

    [HttpGet("two")]
    public IActionResult Two() => Ok();
}

[ApiController]
[Route("api/pp-open")]
public class PpOpenController : ControllerBase
{
    [HttpGet("o")]
    public IActionResult O() => Ok();
}
