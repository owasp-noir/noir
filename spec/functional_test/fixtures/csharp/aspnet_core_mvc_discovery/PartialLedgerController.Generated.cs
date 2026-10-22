using Microsoft.AspNetCore.Mvc;

partial class LedgerController
{
    [HttpPost("import")]
    public IActionResult Import() => Ok();
}
