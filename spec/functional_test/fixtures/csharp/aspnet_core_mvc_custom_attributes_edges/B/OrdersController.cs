using Microsoft.AspNetCore.Mvc;

namespace Fx.B
{
    [ApiRoute("orders")]
    public class OrdersController : Controller
    {
        [HttpGet]
        public IActionResult Index() => Ok();
    }
}
