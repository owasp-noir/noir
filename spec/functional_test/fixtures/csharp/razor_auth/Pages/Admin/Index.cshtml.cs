using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace RazorAuth.Pages.Admin;

[Authorize(Roles = "Admin")]
public class IndexModel : PageModel
{
    public void OnGet() { }
}
