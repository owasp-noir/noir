using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

public class ApiPermissionAttribute : AuthorizeAttribute, IAsyncActionFilter
{
    private readonly string[] permissionIds;

    public ApiPermissionAttribute(params string[] ids) { permissionIds = ids; }

    public Task OnActionExecutionAsync(ActionExecutingContext context, ActionExecutionDelegate next)
    {
        if (permissionIds.Length > 0)
        {
            var hasPermission = context.HttpContext.Context().UserPermissions.Allows(permissionIds[0]);

            if (!hasPermission)
            {
                context.Result = new StatusCodeResult(403);
                return Task.CompletedTask;
            }
        }

        return next();
    }
}

public class ApiPermissionOrAnonymousAttribute(params string[] ids) : ApiPermissionAttribute(ids), IAllowAnonymous
{
}

public class HeaderGateAttribute(string key) : AuthorizeAttribute, IAllowAnonymous, IActionFilter
{
    public void OnActionExecuting(ActionExecutingContext context)
    {
        if (!context.HttpContext.Request.Headers.ContainsKey(key))
        {
            context.Result = new StatusCodeResult(403);
        }
    }

    public void OnActionExecuted(ActionExecutedContext context) { }
}

public class PlainAttribute : Attribute
{
}

public class SecureController : Controller
{
    [HttpGet("secure/guarded")]
    [ApiPermission("read")]
    public IActionResult Guarded() => Ok();

    [HttpGet("secure/open")]
    [ApiPermissionOrAnonymous("read")]
    public IActionResult Open() => Ok();

    [HttpGet("secure/header")]
    [HeaderGate("x-tenant")]
    public IActionResult Header() => Ok();

    [HttpGet("secure/plain")]
    [Plain]
    public IActionResult Plain() => Ok();
}

[ApiPermission]
public class WholeController : Controller
{
    [HttpGet("whole/inside")]
    public IActionResult Inside() => Ok();

    [HttpGet("whole/lifted")]
    [ApiPermissionOrAnonymous]
    public IActionResult Lifted() => Ok();
}
