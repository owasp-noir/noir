[Route("tags")]
public class TagsController : Controller
{
    [HttpGet]
    public IActionResult Get() => Ok();
}
