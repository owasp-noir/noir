using App.Contracts;
using Microsoft.AspNetCore.Mvc;

namespace App.Controllers;

public class PostsController : Controller
{
    [HttpGet(ApiRoutes.Posts.GetAll)]
    public IActionResult GetAll() => Ok();

    [HttpGet(ApiRoutes.Posts.Get)]
    public IActionResult Get([FromRoute] Guid postId) => Ok();

    [HttpPost(ApiRoutes.Posts.Create)]
    public IActionResult Create([FromBody] CreatePost request) => Ok();

    [HttpDelete(ApiRoutes.Posts.Delete)]
    public IActionResult Delete([FromRoute] Guid postId) => Ok();
}

[ApiController]
[Route(ApiRoutes.Base + "/tags")]          // class level: resolved today
public class TagsController : ControllerBase
{
    private const string ById = "{tagId}";

    [HttpGet]
    public IActionResult GetAll() => Ok();

    [HttpGet(ById)]                          // same-class constant
    public IActionResult Get(int tagId) => Ok();

    [HttpPut(ById + "/rename")]              // constant + literal
    public IActionResult Rename(int tagId, [FromBody] string name) => Ok();

    [Route(ById + "/merge"), HttpPost]       // [Route] with a constant
    public IActionResult Merge(int tagId) => Ok();
}

public class CreatePost { public string Name { get; set; } = ""; }
