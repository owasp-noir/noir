using System;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;

namespace Fx.C
{
    // A filter with a Template property is not a route attribute.
    public class ViewTemplateAttribute : ResultFilterAttribute
    {
        public string Template => "labelled";
    }

    [ViewTemplate]
    public class FilteredController : Controller
    {
        [HttpPost("find")]
        public IActionResult Find() => Ok();
    }

    public class RestGetAttribute : HttpGetAttribute
    {
        public RestGetAttribute(string template)
            : base(template)
        {
        }
    }

    public static class Routes
    {
        public const string Item = "item";
    }

    // Property assignments are not constructor arguments; a route argument
    // that is not a literal stays unresolved instead of vanishing.
    [Route("things")]
    public class ThingsController : Controller
    {
        [RestGet("ord", Order = 2, Name = "n")]
        public IActionResult Ordered() => Ok();

        [RestGet(Routes.Item)]
        public IActionResult Item() => Ok();
    }

    // `Get` is also a custom attribute name; a comma in a parameter list is
    // not an attribute list.
    public class GetAttribute : HttpGetAttribute
    {
    }

    public class CommaController : Controller
    {
        [HttpPost("lookup")]
        public IActionResult Lookup(int[] ids, GetAttribute marker) => Ok();
    }
}
