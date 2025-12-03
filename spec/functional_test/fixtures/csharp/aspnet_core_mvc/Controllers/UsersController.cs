using System.Collections.Generic;
using Microsoft.AspNetCore.Mvc;

namespace Demo.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class UsersController : ControllerBase
    {
        [HttpGet]
        public ActionResult<IEnumerable<string>> GetAll([FromHeader] string traceId)
        {
            return Ok();
        }

        [HttpGet("{id:int}")]
        public ActionResult<string> GetById(int id)
        {
            return Ok();
        }

        [HttpPost]
        public IActionResult Create([FromBody] string name)
        {
            return Created("", name);
        }

        [HttpPut("{id}")]
        public IActionResult Update([FromRoute] int id, [FromBody] string name)
        {
            return NoContent();
        }

        [HttpDelete("{id}")]
        public IActionResult Delete(int id, [FromQuery] bool soft)
        {
            return NoContent();
        }
    }
}
