using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

public class UsersModel : PageModel
{
    private readonly IUserService _users;

    [BindProperty(SupportsGet = true)]
    public string Search { get; set; }

    public void OnGet(int page, CancellationToken token) { }

    public async Task<IActionResult> OnPostAsync([FromForm(Name = "user_name")] string name, IUserService svc)
    {
        await Helper.OnPostAsync();
        return Page();
    }

    public IActionResult OnPostDelete(int id) => RedirectToPage();
}
