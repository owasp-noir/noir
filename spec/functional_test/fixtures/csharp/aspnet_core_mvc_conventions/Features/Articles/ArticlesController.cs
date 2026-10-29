namespace App.Features.Articles;

[Route("articles")]
public class ArticlesController : Controller
{
    [HttpPost]
    public IActionResult Create([FromBody] Create.Command command) => Ok(command);
}
