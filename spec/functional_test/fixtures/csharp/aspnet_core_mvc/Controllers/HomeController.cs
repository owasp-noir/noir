using Microsoft.AspNetCore.Mvc;

namespace Demo.Controllers
{
    public class HomeController : Controller
    {
        public IActionResult Index()
        {
            return View();
        }

        public IActionResult About()
        {
            return View();
        }

        [HttpPost]
        public IActionResult Save([FromForm] string name, [FromForm] string description)
        {
            return RedirectToAction("Index");
        }

        public IActionResult Details(int id)
        {
            return View();
        }
    }
}
