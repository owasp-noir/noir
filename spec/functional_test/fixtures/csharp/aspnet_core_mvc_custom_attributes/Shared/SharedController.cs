using Microsoft.AspNetCore.Mvc;

namespace Fx.Shared
{
    // Served by Host (FallbackPolicy) and by Host2 (no policy): open there.
    [Route("shared")]
    public class SharedController : Controller
    {
        [HttpGet]
        public IActionResult Index()
        {
            return Ok();
        }
    }
}
