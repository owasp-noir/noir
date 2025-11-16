using System.Web.Mvc;

namespace MyApp.Controllers
{
    [Route("api/[controller]")]
    public class ApiController : Controller
    {
        // GET: /api/Api/users/{id}
        [HttpGet("users/{id}")]
        public ActionResult GetUser([FromRoute] int id, [FromHeader] string authorization)
        {
            return View();
        }
        
        // POST: /api/Api/users
        [HttpPost("users")]
        public ActionResult CreateUser([FromBody] string userData, [FromHeader] string apiKey)
        {
            return View();
        }
        
        // PUT: /api/Api/products/{productId}
        [HttpPut("products/{productId}")]
        public ActionResult UpdateProduct([FromRoute] int productId, [FromBody] string productData, [FromHeader] string contentType)
        {
            return View();
        }
        
        // DELETE: /api/Api/items/{itemId}
        [HttpDelete("items/{itemId}")]
        public ActionResult DeleteItem([FromRoute] int itemId, [FromQuery] bool confirm, [FromHeader] string authorization)
        {
            return View();
        }
        
        // GET: /api/Api/search
        [HttpGet("search")]
        public ActionResult Search([FromQuery] string term, [FromQuery] int page, [FromHeader] string acceptLanguage)
        {
            return View();
        }
        
        // POST: /api/Api/upload
        [HttpPost("upload")]
        public ActionResult Upload([FromForm] string fileName, [FromForm] string description, [FromHeader] string contentType)
        {
            return View();
        }
        
        // GET: /api/Api/profile
        [HttpGet("profile")]
        public ActionResult GetProfile([FromCookie] string sessionId, [FromCookie] string preferences)
        {
            return View();
        }
    }
}
