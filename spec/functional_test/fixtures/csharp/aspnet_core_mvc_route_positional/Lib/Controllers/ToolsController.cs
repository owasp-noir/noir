using Microsoft.AspNetCore.Mvc;

namespace App.Lib.Controllers
{
    public class ToolsController : Controller
    {
        public IActionResult Details(int id)
        {
            return View();
        }
    }
}
