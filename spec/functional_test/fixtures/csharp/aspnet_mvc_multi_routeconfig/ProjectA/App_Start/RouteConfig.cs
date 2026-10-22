using System.Web.Mvc;
using System.Web.Routing;

namespace ProjectA
{
    public class RouteConfig
    {
        public static void RegisterRoutes(RouteCollection routes)
        {
            routes.MapRoute(
                name: "Default",
                url: "routeA/{controller}/{action}/{id}",
                defaults: new { controller = "HomeA", action = "Index", id = UrlParameter.Optional }
            );
        }
    }
}
