using Microsoft.AspNetCore.Mvc;

namespace Fx.Http
{
    // No `Controller` word of its own: reached only through its base.
    public abstract class RestControllerWithSignalR<TResource, TModel> : RestController<TResource>, IHandle<TModel>
        where TResource : class, new()
        where TModel : class, new()
    {
        [HttpDelete("{id:int}")]
        public virtual IActionResult DeleteResource(int id)
        {
            return Ok();
        }
    }
}
