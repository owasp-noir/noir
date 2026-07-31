using Microsoft.AspNetCore.Mvc;

namespace Demo.Controllers
{
    // [AcceptVerbs] declares one action answering several verbs, optionally at
    // its own route. [From*(Name = "…")] rebinds a parameter to the name the
    // client actually sends. A `{id=5}` segment carries a template default,
    // which is not part of the URL.
    [Route("banks")]
    public class BanksController : ControllerBase
    {
        [AcceptVerbs("PUT", "PATCH")]
        public IActionResult Update(string accountNumber) => Ok(accountNumber);

        [AcceptVerbs("PUT", "POST", Route = "transfer")]
        public IActionResult Transfer([FromForm] string amount) => Ok(amount);

        [HttpGet("branch/{branchId}")]
        public IActionResult Branch([FromRoute(Name = "branchId")] string internalBranchKey) =>
            Ok(internalBranchKey);

        [HttpGet("page/{page=5}")]
        public IActionResult Page(int page) => Ok(page);

        [HttpGet("audit")]
        public IActionResult Audit([FromHeader(Name = "X-Tenant")] string tenant) => Ok(tenant);
    }
}
