using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;

namespace App.Filters;

// Refuses unless the permission service grants a permission: which roles
// hold it is data, so configuration decides.
public sealed class RequireAdminAttribute : TypeFilterAttribute
{
    public RequireAdminAttribute(bool ignore = false) : base(typeof(RequireAdminFilter))
    {
        Arguments = [ignore];
    }

    private class RequireAdminFilter : IAsyncAuthorizationFilter
    {
        private readonly bool _ignore;
        private readonly IPermissionService _permissionService;

        public RequireAdminFilter(bool ignore, IPermissionService permissionService)
        {
            _ignore = ignore;
            _permissionService = permissionService;
        }

        public async Task OnAuthorizationAsync(AuthorizationFilterContext context)
        {
            if (_ignore)
                return;

            if (!await _permissionService.AuthorizeAsync("AccessAdminPanel"))
                context.Result = new ChallengeResult();
        }
    }
}

// Refuses an unauthenticated caller outright.
public class SignedInAttribute : Attribute, IAuthorizationFilter
{
    public void OnAuthorization(AuthorizationFilterContext context)
    {
        if (context.HttpContext.User.Identity?.IsAuthenticated != true)
            context.Result = new UnauthorizedResult();
    }
}

// Never refuses: it only redirects a closed store.
public class StoreClosedAttribute : Attribute, IActionFilter
{
    public void OnActionExecuting(ActionExecutingContext context)
    {
        if (StoreSettings.Closed)
            context.Result = new RedirectToRouteResult("StoreClosed", null);
    }

    public void OnActionExecuted(ActionExecutedContext context)
    {
    }
}
