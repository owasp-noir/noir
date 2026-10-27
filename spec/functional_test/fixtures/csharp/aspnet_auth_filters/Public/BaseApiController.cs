using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace App.Public;

[AllowAnonymous]
public abstract partial class BaseApiController : ControllerBase
{
}
