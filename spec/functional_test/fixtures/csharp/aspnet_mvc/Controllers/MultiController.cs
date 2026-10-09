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
}
