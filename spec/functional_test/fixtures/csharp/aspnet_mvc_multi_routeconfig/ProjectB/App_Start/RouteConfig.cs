using System.Web.Mvc;
using System.Web.Routing;

namespace ProjectB
{
    public class RouteConfig
    {
        public static void RegisterRoutes(RouteCollection routes)
        {
            routes.IgnoreRoute("{resource}.axd/{*pathInfo}");

            routes.MapRoute(
                name: "Default",
                url: "routeB/{controller}/{action}/{id}",
                defaults: new { controller = "HomeB", action = "Index", id = UrlParameter.Optional }
            );
        }
    }
}
