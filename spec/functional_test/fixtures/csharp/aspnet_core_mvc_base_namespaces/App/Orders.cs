using Microsoft.AspNetCore.Mvc;

namespace App.Controllers;

// No `using` picks one of the two ApiController declarations: no prefix is guessed.
public class OrdersController : ApiController
{
    [HttpGet("orders")]
    public IActionResult List() => Ok();
}
