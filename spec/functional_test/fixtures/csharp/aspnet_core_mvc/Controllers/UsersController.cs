using System.Collections.Generic;
using System.Threading.Tasks;
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

        [HttpGet("raw")]
        public Task<IEnumerable<string>> Raw([FromQuery] string filter, [FromServices] IUserRepository repository)
        {
            return repository.List(filter);
        }

        [HttpGet("search")]
        public IActionResult Search(string keyword, IUserRepository repository)
        {
            return Ok(repository.List(keyword));
        }

        [NonAction]
        public Task<UserDto> LoadUser([FromQuery] string id)
        {
            return Task.FromResult(new UserDto());
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

    public interface IUserRepository
    {
        Task<IEnumerable<string>> List(string filter);
    }

    public class UserDto
    {
    }
}
