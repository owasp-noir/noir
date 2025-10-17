using System.Web.Mvc;

namespace MyApp.Controllers
{
    public class ProductController : Controller
    {
        // GET: /Product/List
        [HttpGet]
        public ActionResult List(int categoryId, string sortBy)
        {
            return View();
        }
        
        // POST: /Product/Add
        [HttpPost]
        public ActionResult Add(string productName, decimal price, int stock)
        {
            return View();
        }
    }
}
