using Microsoft.AspNetCore.Mvc;
using TodoApi.Models;

namespace TodoApi.Controllers;

// Shape of the official "Create a controller-based web API" tutorial:
// [ApiController] infers [FromBody] for complex types and [FromQuery] for
// simple types that are not route values.
[Route("api/[controller]")]
[ApiController]
public class TodoItemsController : ControllerBase
{
    [HttpPost]
    public async Task<ActionResult<TodoItem>> PostTodoItem(TodoItem todoItem) => Ok();

    [HttpPut("{id}")]
    public async Task<IActionResult> PutTodoItem(long id, TodoItem todoItem) => NoContent();

    [HttpPost("{id}/complete")]
    public IActionResult Complete(long id, bool notify) => NoContent();

    [HttpPost("upload")]
    public IActionResult Upload(IFormFile file, string note) => Ok();
}
