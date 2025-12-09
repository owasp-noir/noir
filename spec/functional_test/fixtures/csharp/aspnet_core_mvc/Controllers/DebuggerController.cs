using System.Text.Json;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;

namespace Demo.Controllers
{
    public class DebuggerController : Controller
    {
        [HttpGet("expression/null")]
        public async Task<IActionResult> Nulls(int? intValue = null, string strValue = null, bool? boolValue = null)
        {
            await Task.CompletedTask;
            return Content($"Nulls {intValue}-{strValue}-{boolValue}");
        }

        [HttpGet("expression/nulldefault")]
        public async Task<IActionResult> NullDefaults(int? intValue = null, string strValue = null, bool? boolValue = null)
        {
            await Task.CompletedTask;
            return Content($"Defaults {intValue}-{strValue}-{boolValue}");
        }

        [HttpGet("debug/headers")]
        public IActionResult Headers()
        {
            var header = Request.Headers["X-Debug"];
            return Content(header);
        }

        [HttpGet("debug/cookies")]
        public IActionResult Cookies()
        {
            var cookie = Request.Cookies["sessionId"];
            return Content(cookie);
        }

        [HttpPost("debug/form")]
        public IActionResult FormReader()
        {
            var val = Request.Form["extra"];
            return Content(val);
        }

        [HttpPost("debug/json")]
        public async Task<IActionResult> JsonReader()
        {
            using var doc = await System.Text.Json.JsonDocument.ParseAsync(Request.Body);
            var root = doc.RootElement;
            var id = root.GetProperty("id").GetString();
            return Content(id);
        }
    }
}
