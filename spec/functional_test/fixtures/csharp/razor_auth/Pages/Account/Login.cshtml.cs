using Microsoft.AspNetCore.Authorization;

namespace RazorAuth.Pages.Account;

[AllowAnonymous]
public class LoginModel : SecurePageModel
{
    public void OnGet() { }
}
