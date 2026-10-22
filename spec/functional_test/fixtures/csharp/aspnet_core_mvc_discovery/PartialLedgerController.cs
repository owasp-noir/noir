using Microsoft.AspNetCore.Mvc;

public partial class LedgerController : ControllerBase
{
    [HttpGet("summary")]
    public IActionResult Summary() => Ok();
}
