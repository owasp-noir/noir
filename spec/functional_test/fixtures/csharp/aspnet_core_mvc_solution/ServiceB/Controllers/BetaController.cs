using Microsoft.AspNetCore.Mvc;

namespace ServiceB.Controllers
{
    public class BetaController : Controller
    {
        public IActionResult Show(int id)
        {
            return View();
        }
    }
}
