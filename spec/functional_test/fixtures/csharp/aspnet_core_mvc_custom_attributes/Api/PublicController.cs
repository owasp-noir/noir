using Fx.Http;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Fx.Api
{
    // Opts out of the host's FallbackPolicy; its inherited GET by id follows.
    [V3ApiController("public")]
    [AllowAnonymous]
    public class PublicController : RestController<TagResource>
    {
    }
}
