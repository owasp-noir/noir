using Microsoft.AspNetCore.Mvc;

namespace App.Controllers
{
    public class HomeController : Controller
    {
        public IActionResult Index()
        {
            return View();
        }

        public IActionResult Details(int id)
        {
            return View();
        }
    }
}

namespace App.Areas.Admin.Controllers
{
    [Area("Admin")]
    public class DashboardController : Controller
    {
        public IActionResult Index()
        {
            return View();
        }
    }
}

namespace App.Areas.Shop.Controllers
{
    // No route the host declares reaches the Shop area.
    [Area("Shop")]
    public class CartController : Controller
    {
        public IActionResult Index()
        {
            return View();
        }
    }
}
