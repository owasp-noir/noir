using System.Web;
using System.Web.Mvc;

namespace App.Controllers
{
    public class AccountController : Controller
    {
        public ActionResult Login(string returnUrl) { return View(); }

        [AcceptVerbs(HttpVerbs.Post)]
        public ActionResult Save(string name) { return View(); }

        [AcceptVerbs(HttpVerbs.Get | HttpVerbs.Post)]
        public ActionResult Both(int id) { return View(); }

        [AcceptVerbs("PUT")]
        public ActionResult Replace(int id) { return View(); }

        // The scaffolded MVC 5 delete pair: both answer on /Account/Delete.
        public ActionResult Delete(int id) { return View(); }

        [HttpPost, ActionName("Delete")]
        [ValidateAntiForgeryToken]
        public ActionResult DeleteConfirmed(int id) { return View(); }
    }
}
