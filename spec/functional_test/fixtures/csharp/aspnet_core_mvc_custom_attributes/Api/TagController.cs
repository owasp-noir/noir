using Fx.Http;
using Microsoft.AspNetCore.Mvc;

namespace Fx.Api
{
    [V3ApiController("tag")]
    public class TagController : RestControllerWithSignalR<TagResource, TagModel>
    {
        [HttpGet]
        public ActionResult<TagResource> GetAll()
        {
            return Ok();
        }
    }

    // Overrides the inherited GET by id: the controller's own wins.
    [V3ApiController]
    public class SeriesController : RestControllerWithSignalR<TagResource, TagModel>
    {
        [NonAction]
        public override ActionResult<TagResource> GetResourceByIdWithErrorHandler(int id)
        {
            return base.GetResourceByIdWithErrorHandler(id);
        }

        [RestGetById]
        public ActionResult<TagResource> GetResourceByIdWithErrorHandler(int id, [FromQuery] bool includeImages = false)
        {
            return Ok();
        }

        [HttpGet("lookup")]
        public ActionResult Lookup([FromQuery] string term)
        {
            return Ok();
        }
    }

    [V5ApiController("calendar")]
    public class CalendarController : Controller
    {
        [HttpGet]
        public IActionResult GetCalendar()
        {
            return Ok();
        }
    }

    // A marker attribute that only looks like a route attribute is not one.
    [Label]
    public class LabelController : Controller
    {
        [HttpGet("label")]
        public IActionResult Show()
        {
            return Ok();
        }
    }

    public class TagModel
    {
    }

    public class TagResource
    {
        public int Id { get; set; }
        public string Label { get; set; }
    }
}
