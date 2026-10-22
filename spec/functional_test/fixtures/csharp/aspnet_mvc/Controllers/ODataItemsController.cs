using System.Web.Http;
using System.Web.OData;

namespace MyApp.Controllers.OData
{
    // Web API / OData: routed by verb convention, not by MVC's
    // {controller}/{action}.
    public class ItemsController : WebApiEntityController<Item>
    {
        public IHttpActionResult Get(int key)
        {
            return Ok(key);
        }
    }
}
