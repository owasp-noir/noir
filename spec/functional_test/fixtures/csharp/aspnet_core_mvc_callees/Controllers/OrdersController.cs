using Microsoft.AspNetCore.Mvc;

namespace Demo.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class OrdersController : ControllerBase
    {
        [HttpGet("{id}")]
        public IActionResult Show([FromRoute] int id)
        {
            var order = orderService.Load(id);
            AuditLog.Write("core:show");
            return Ok(SerializeOrder(order));
        }

        [HttpPost]
        public IActionResult Create([FromBody] string name)
        {
            var order = orderService.Create(name);
            return Created("", SerializeOrder(order));
        }
    }
}
