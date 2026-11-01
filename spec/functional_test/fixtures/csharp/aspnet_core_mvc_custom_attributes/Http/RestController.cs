using Microsoft.AspNetCore.Mvc;

namespace Fx.Http
{
    public abstract class RestController<TResource> : Controller
    {
        [RestGetById]
        public virtual ActionResult<TResource> GetResourceByIdWithErrorHandler(int id)
        {
            return Ok();
        }

        [RestPutById]
        public virtual ActionResult<TResource> UpdateResource([FromBody] TResource resource)
        {
            return Ok();
        }

        [RestPostById]
        public virtual ActionResult<TResource> CreateResource([FromBody] TResource resource)
        {
            return Ok();
        }

        public virtual void NotAnAction()
        {
        }
    }
}
