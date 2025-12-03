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
    }
}
