using System.Web.Mvc;

namespace Demo.Controllers
{
    public class ShopController : Controller
    {
        public ActionResult Details(int id)
        {
            var item = shopService.Load(id);
            AuditLog.Write("mvc:details");
            return View(SerializeItem(item));
        }

        [HttpPost]
        public ActionResult Create(string name, string email)
        {
            var item = shopService.Create(name, email);
            return Json(SerializeItem(item));
        }
    }
}
