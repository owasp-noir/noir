using Microsoft.AspNetCore.Mvc;
using Web.Infrastructure;

namespace Plugin.Controllers;

public class NewsController : Controller
{
    public IActionResult List()
    {
        return View();
    }

    public IActionResult ListRss(int languageId)
    {
        return Content("<rss/>");
    }
}

[Area(AreaNames.ADMIN)]
public class NewsAdminController : Controller
{
    public IActionResult NewsItemEdit(int id)
    {
        return View();
    }

    [HttpPost]
    public IActionResult Delete(int id)
    {
        return RedirectToAction("List");
    }
}
