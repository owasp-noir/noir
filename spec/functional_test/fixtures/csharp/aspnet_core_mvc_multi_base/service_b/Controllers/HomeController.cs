using Microsoft.AspNetCore.Mvc;

public class HomeController : Controller {
    public IActionResult Index() {
        return Ok("b");
    }
}
