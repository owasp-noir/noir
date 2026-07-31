using Microsoft.AspNetCore.Mvc;

namespace ServiceA.Controllers
{
    public class AlphaController : Controller
    {
        public IActionResult Index()
        {
            return View();
        }
    }
}
