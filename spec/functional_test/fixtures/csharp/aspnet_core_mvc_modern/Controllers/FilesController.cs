using Microsoft.AspNetCore.Mvc;

namespace Demo.Controllers
{
    // A single action carrying more than one [Http*] attribute — the GET+HEAD
    // pair used for file/image serving, and a GET+POST search action — must
    // emit an endpoint per verb, not only the last attribute.
    [Route("")]
    public class FilesController : ControllerBase
    {
        [HttpGet("Files/{id}/Download")]
        [HttpHead("Files/{id}/Download")]
        public IActionResult Download(string id) => File(id, "application/octet-stream");

        [HttpGet("Files/Search")]
        [HttpPost("Files/Search")]
        public IActionResult Search([FromQuery] string q) => Ok(q);
    }
}
