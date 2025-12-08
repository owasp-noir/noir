using Microsoft.AspNetCore.Mvc;

namespace Demo.Controllers
{
    [Route("admin")]
    public class AdminController : Controller
    {
        [HttpGet("[action]")]
        public IActionResult Dashboard()
        {
            return View();
        }

        [HttpGet("reports/{year:int}/{month:int?}")]
        public IActionResult Reports([FromRoute] int year, [FromRoute] int month)
        {
            return View();
        }

        [HttpPost("[action]")]
        public IActionResult Notify([FromForm] string subject, [FromForm] string message, string sessionId)
        {
            return View();
        }
    }
}
