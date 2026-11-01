using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Shapes.Controllers;

[ApiController]
[Route("api/orders")]
public class OrdersController : ControllerBase
{
    // S1: verb after another attribute in one list
    [Authorize, HttpPost("create")]
    public IActionResult Create([FromBody] OrderDto dto) => Ok();

    // S2: two verbs in one list
    [HttpGet("feed"), HttpHead("feed")]
    public IActionResult Feed() => Ok();

    // S3: named template argument
    [HttpGet(template: "named/{id}")]
    public IActionResult Named(int id) => Ok();

    // S4: Order/Name property arguments around the template
    [HttpGet("by/{id}", Order = 2, Name = "ById")]
    public IActionResult ById(int id) => Ok();

    // S5: a class-level string that spells an attribute
    private const string Doc = "[HttpDelete(\"phantom\")] public IActionResult X()";

    [HttpGet("after-doc")]
    public IActionResult AfterDoc() => Ok();

    /* S6: commented-out action
    [HttpPut("ghost")]
    public IActionResult Ghost() { return Ok(); }
    */

    // S7: raw string field holding attribute-looking lines
    private const string Raw = """
        [HttpPost("raw")]
        public IActionResult Raw() { }
        """;

    [HttpGet("after-raw")]
    public IActionResult AfterRaw() => Ok("}");

    // S8: signature split before the name
    [HttpGet("split/{id}")]
    public async Task<IActionResult>
        Split(int id)
    {
        await Task.Delay(1);
        return Ok();
    }

    // S9: parameter attributes, defaults with commas and brackets
    [HttpGet("search")]
    public IActionResult Search(
        [FromQuery(Name = "q")] string query = "a,b",
        [FromHeader(Name = "X-Trace")] string trace = "[x]",
        int page = 1)
    {
        return Ok();
    }

    // S10: attribute on the same line, trailing comment with a brace
    [HttpDelete("{id}")] // removes {
    public IActionResult Remove(int id) => Ok();

    // S11: attribute args split over lines with a lambda-free nested paren
    [HttpPatch(
        "patch/{id}",
        Name = "Patch(1)")]
    public IActionResult Patch(int id) => Ok();

    // S12: generic action and tuple return
    [HttpGet("tuple")]
    public (int, string) Tuple() => (1, "a");

    // S13: public method below a local function-looking string
    [HttpPost("ops")]
    public IActionResult Ops([FromForm] string op) { var s = "public IActionResult Fake() {"; return Ok(s); }

    // S14: #if between attributes
    [HttpGet("cond")]
#if DEBUG
    [ProducesResponseType(200)]
#endif
    public IActionResult Cond() => Ok();
}

public record OrderDto(string Item, int Quantity);
