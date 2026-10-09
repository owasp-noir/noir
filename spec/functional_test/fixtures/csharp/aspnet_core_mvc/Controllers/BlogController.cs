using Microsoft.AspNetCore.Mvc;

namespace Demo.Controllers
{
    public class BlogController : Controller
    {
        public IActionResult Show(int year, string slug)
        {
            return View();
        }
    }
}
