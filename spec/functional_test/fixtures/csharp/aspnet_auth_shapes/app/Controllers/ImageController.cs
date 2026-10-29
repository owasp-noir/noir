using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

[ApiController]
[Route("")]
public class ImageController : ControllerBase
{
    [HttpPost("Users/{userId}/Images/{index}")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status409Conflict)]
    [ProducesResponseType(StatusCodes.Status500InternalServerError)]
    [ProducesResponseType(StatusCodes.Status503ServiceUnavailable)]
    [ProducesResponseType(StatusCodes.Status507InsufficientStorage)]
    public IActionResult Upload([FromRoute] string userId, [FromRoute] int index) => NoContent();
}

[ApiController]
[Route("Admin")]
[Authorize(Policy = "Admin")]
public class AdminController : ControllerBase
{
    [HttpGet("Ping")]
    [AllowAnonymous]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status409Conflict)]
    public IActionResult Ping() => Ok();

    [HttpGet("Stats")]
    public IActionResult Stats() => Ok();
}
