using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace MyApp.Controllers
{
    [Authorize]
    [ApiController]
    [Route("api/[controller]")]
    public class PostsController : ControllerBase
    {
        [AllowAnonymous]
        [HttpGet]
        public IActionResult Index()
        {
            return Ok(new { message = "public" });
        }

        [HttpGet("{id}")]
        public IActionResult Show(int id)
        {
            return Ok(new { id = id });
        }

        [Authorize(Roles = "Admin")]
        [HttpPost]
        public IActionResult Create()
        {
            return Ok(new { created = true });
        }
    }
}
