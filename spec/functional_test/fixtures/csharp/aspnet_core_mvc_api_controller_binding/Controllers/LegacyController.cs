using Microsoft.AspNetCore.Mvc;
using TodoApi.Models;

namespace TodoApi.Controllers;

// Control: a plain MVC controller (no [ApiController]) binds the same
// parameter from the form, which is what noir reports today.
public class LegacyController : Controller
{
    [HttpPost]
    public IActionResult Save(TodoItem todoItem) => View();
}
