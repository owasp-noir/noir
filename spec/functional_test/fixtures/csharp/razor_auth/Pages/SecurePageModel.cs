using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace RazorAuth.Pages;

[Authorize]
public abstract class SecurePageModel : PageModel
{
}
