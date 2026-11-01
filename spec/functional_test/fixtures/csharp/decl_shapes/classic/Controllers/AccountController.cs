using System.Web.Mvc;

namespace Classic.Controllers
{
    [Authorize]
    [RoutePrefix("account")]
    public class AccountController : Controller
    {
        // K1: verb after another attribute in one list
        [ValidateAntiForgeryToken, HttpPost]
        [Route("login")]
        public ActionResult Login(string user, string returnUrl = "/a,b") { return View(); }

        // K2: a string field spelling an attribute
        private const string Hint = "[HttpDelete] public ActionResult Gone()";

        [Route("profile")]
        public ActionResult Profile() { return View(); }

        // K3: split signature
        [HttpGet]
        [Route("orders/{id}")]
        public ActionResult
            Orders(int id) { return View(); }

        // K4: [AllowAnonymous] with trailing comment ending in ';'
        [AllowAnonymous] // public;
        [Route("register")]
        public ActionResult Register() { return View(); }
    }
}
