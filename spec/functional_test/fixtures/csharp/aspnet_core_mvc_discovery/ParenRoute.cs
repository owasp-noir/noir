using Microsoft.AspNetCore.Mvc;

[Route("paren")]
public class ParenRouteController : ControllerBase
{
    [HttpGet("first")]
    public IActionResult First() => Ok();

    [HttpGet("smile-(-face")]
    public IActionResult Smile() => Ok();
}
