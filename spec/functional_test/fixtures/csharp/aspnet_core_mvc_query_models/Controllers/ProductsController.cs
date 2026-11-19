using Microsoft.AspNetCore.Mvc;
using App.Models;

namespace App.Controllers;

[ApiController]
[Route("api/products")]
public class ProductsController : ControllerBase
{
    [HttpGet]
    public IActionResult Search([FromQuery] ProductQuery query) => Ok();

    [HttpGet("export")]
    public IActionResult Export([FromQuery] ProductQuery query, [FromQuery] string format) => Ok();

    // Control: the same expansion already happens for a body DTO.
    [HttpPost]
    public IActionResult Create([FromBody] CreateProduct product) => Ok();
}
