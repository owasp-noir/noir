using Microsoft.AspNetCore.Mvc;

[Route("actions")]
public class ActionsController : ControllerBase
{
    [NonAction]
    private IActionResult Helper() => Ok();

    [HttpGet("live")]
    public IActionResult Read() => Ok();

    [NonAction]
    protected IActionResult OtherHelper()
    {
        return Ok();
    }

    [HttpPost("live")]
    public IActionResult Create() => Ok();

    [NonAction]
    [HttpDelete("excluded")]
    public IActionResult Excluded() => Ok();

    // [HttpDelete("line-comment")]
    // public IActionResult Removed() => Ok();

    /*
    [HttpPut("block-comment")]
    public IActionResult RemovedBlock() => Ok();
    */

    /// <example>
    /// [HttpPatch("doc-comment")]
    /// public IActionResult RemovedExample() => Ok();
    /// </example>
    [HttpGet("documented")]
    public IActionResult Documented() => Ok("https://example.invalid/a/*literal*/");
}
