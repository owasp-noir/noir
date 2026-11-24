using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace RazorAuth.Pages.Basket;

[Authorize]
public class CheckoutModel : PageModel
{
    public void OnGet() { }

    public IActionResult OnPost() => RedirectToPage("Success");
}
