using Microsoft.AspNetCore.Mvc;

[Route("returns")]
public class ReturnTypesController : ControllerBase
{
    [HttpGet("nullable")]
    public ActionResult<string?> Nullable() => Ok();

    [HttpGet("task-nullable")]
    public async Task<long?> TaskNullable() => Ok();

    [HttpGet("qualified")]
    public async Task<Sample.Models.ListResponse<string>> Qualified() => Ok();

    [HttpPost("record-parameter")]
    public IActionResult Save(AuditRecord record) => Ok();
}
