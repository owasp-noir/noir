using System.Web.Mvc;

namespace MyApp.Controllers
{
    public class UserController : Controller
    {
        // GET: /User/Details/{id}
        public ActionResult Details(int id)
        {
            return View();
        }
        
        // GET: /User/Search
        public ActionResult Search(string query, int page)
        {
            return View();
        }
        
        // POST: /User/Create
        [HttpPost]
        public ActionResult Create(string name, string email)
        {
            return View();
        }
        
        // PUT: /User/Update
        [HttpPut]
        public ActionResult Update(int id, string name)
        {
            return View();
        }
        
        // DELETE: /User/Delete/{id}
        [HttpDelete]
        public ActionResult Delete(int id)
        {
            return View();
        }
    }
}
