using ServiceStack;
using Microsoft.AspNetCore.Mvc;

namespace ServiceStackDemo.Controllers
{
    // Not a ServiceStack request DTO: an MVC controller that happens to sit
    // in a project that also references ServiceStack. The [Route] attribute
    // here decorates a Controller class, not a request DTO — the
    // ServiceStack analyzer must not treat it as one (that's the
    // project-scoping "don't steal ASP.NET MVC's [Route]" concern).
    [Route("api/[controller]")]
    public class UnrelatedController : Controller
    {
        [HttpGet]
        public IActionResult Get() => Ok();
    }
}
