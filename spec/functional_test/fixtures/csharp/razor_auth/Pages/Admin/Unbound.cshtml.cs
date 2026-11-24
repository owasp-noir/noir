using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace RazorAuth.Pages.Admin;

[Authorize(Roles = "Admin")]
public class UnboundModel : PageModel
{
}
