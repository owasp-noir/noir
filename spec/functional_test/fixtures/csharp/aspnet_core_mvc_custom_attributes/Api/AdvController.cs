using Fx.Http;
using Microsoft.AspNetCore.Mvc;

namespace Fx.Api
{
    [V3ApiController("adv")]
    public class AdvController : Controller
    {
        // Mid-list: the custom attribute is not the first of its list.
        [Produces("application/json"), RestGetById]
        public IActionResult One(int id) => Ok();

        // [RestGetById]
        [HttpGet("plain")]
        public IActionResult Plain() => Ok();

        // A name inside a string is text, not an attribute of the next member.
        private const string Doc = "[RestGetById] is documented here";

        [HttpGet("after-string")]
        public IActionResult After() => Ok();
    }
}
