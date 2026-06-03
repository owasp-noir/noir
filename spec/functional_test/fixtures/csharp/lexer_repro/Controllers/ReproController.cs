using Microsoft.AspNetCore.Mvc;

namespace Demo.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class ReproController : ControllerBase
    {
        // BUG 1: a `}` inside a string literal makes the brace counter hit 0
        // early, so every callee below the string line is dropped.
        [HttpGet("dirty/{id}")]
        public IActionResult Dirty([FromRoute] int id)
        {
            var json = LoadTemplate("a } brace in string");
            SecretHelperCall(id);
            AuditLog.Write("dirty");
            return Ok(SerializeOrder(json));
        }

        // BUG 2: an unbalanced `(` inside a string default keeps the paren
        // counter > 0, so the signature runs away and both params are lost.
        [HttpGet("calc")]
        public IActionResult Calc(
            [FromQuery] string expr = "2 * (3 + 4",
            [FromQuery] int limit = 10)
        {
            return Ok(Compute(expr, limit));
        }
    }
}
