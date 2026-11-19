using Microsoft.AspNetCore.Mvc;

namespace App.Controllers;

// Conventionally routed MVC controller: every public instance method is an
// action, whatever it returns.
public class DocumentsController : Controller
{
    public IActionResult Index() => View();                              // found
    public FileResult Download(int id) => File("a.pdf", "application/pdf");
    public FileStreamResult Stream(string path) => null!;
    public FileContentResult Export(string format) => null!;
    public PhysicalFileResult Raw(string name) => null!;
    public ContentResult Robots() => Content("User-agent: *");
    public RedirectResult Go(string url) => Redirect(url);
    public LocalRedirectResult Back(string returnUrl) => LocalRedirect(returnUrl);
    public StatusCodeResult Health() => Ok();
    public string Version() => "1.0";
    public async Task<string> Motd() => "hi";
    public async Task Logout() { await HttpContext.SignOutAsync(); }
    public IEnumerable<string> Tags() => new[] { "a" };

    [NonAction]
    public string Helper() => "";                                        // correctly absent
    private IActionResult Hidden() => View();                            // correctly absent
    public static string Shared() => "";                                 // static: not an action
    public override void OnActionExecuting(ActionExecutingContext context) { }
    protected override void Dispose(bool disposing) { }
}
