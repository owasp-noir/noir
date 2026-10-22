using System.Web.Mvc;

namespace MyApp.Controllers
{
    // Several controllers in one file, deriving from a local base class.
    public class FirstController : BaseController
    {
        public ActionResult Index()
        {
            return View();
        }

        public JsonResult Data(int id)
        {
            return Json(id, JsonRequestBehavior.AllowGet);
        }

        // Nested helper type: its members are not actions, but the actions
        // after it still belong to FirstController.
        public class Paging
        {
            public ActionResult NotAnAction(int page) { return null; }
        }

        public async Task<FileResult> Download(string name)
        {
            return File(name, "application/octet-stream");
        }

        // The literal belongs to FormValueRequired, not to the route.
        [HttpPost, FormValueRequired("save-continue")]
        public ActionResult Save(int id, bool continueEditing = false /* flag */)
        {
            return View();
        }
    }

    [RoutePrefix("second")]
    public class SecondController : BaseController
    {
        [Route("other")]
        public ActionResult Other(string x)
        {
            return View();
        }
    }

    public class ThirdController : BaseController
    {
        public ContentResult Third(string x)
        {
            return Content(x);
        }
    }

    public class OrderViewModel
    {
        public ActionResult Ignored(string y) { return null; }
    }

    // None of these are routable actions.
    public abstract class SharedBaseController : Controller
    {
        public ActionResult Shared() { return View(); }
    }

    public class GenericController<T> : Controller where T : class
    {
        public ActionResult List() { return View(); }
    }

    public class CacheController : IDisposable
    {
        public ActionResult Bogus() { return null; }
        public void Dispose() { }
    }

    public class LegacyApiController : BaseApiController
    {
        public IHttpActionResult Get(int id) { return Ok(); }
    }

    public class FourthController : SharedBaseController
    {
        [NonAction]
        public ActionResult Helper() { return null; }

        [OutputCache(Duration = 60), ChildActionOnly]
        public ActionResult Menu() { return PartialView(); }

        public static ActionResult Stat() { return null; }

        private ActionResult Priv(string publicKey) { return null; }

        public HttpResponseMessage Raw() { return null; }

        public ActionResult Visible() { return View(); }
    }
}
