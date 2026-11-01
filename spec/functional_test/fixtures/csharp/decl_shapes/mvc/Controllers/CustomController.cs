using Microsoft.AspNetCore.Mvc;
using Shapes.Attributes;

namespace Shapes.Controllers;

[ApiController]
[VersionedApi("books", 3, Name = "b")]
public class BooksController : ControllerBase
{
    [GetById]
    public IActionResult Get(int id) => Ok();

    // C3: filter with Template property must not route
    [Audit(Template = "x")]
    [HttpGet("list")]
    public IActionResult List() => Ok();

    // C4: comma in parameter list must not read as attribute
    [HttpPost("bulk")]
    public IActionResult Bulk([FromBody] string a, GetById b) => Ok();
}
