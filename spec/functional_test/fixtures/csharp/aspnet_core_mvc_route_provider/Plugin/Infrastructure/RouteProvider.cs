using Microsoft.AspNetCore.Routing;
using Web.Infrastructure;

namespace Plugin.Infrastructure;

public class RouteProvider : BaseRouteProvider, IRouteProvider
{
    public void RegisterRoutes(IEndpointRouteBuilder endpointRouteBuilder)
    {
        endpointRouteBuilder.MapControllerRoute(name: "NewsArchive",
            pattern: $"{GetLanguageRoutePattern()}/news",
            defaults: new { controller = "News", action = "List" });

        endpointRouteBuilder.MapControllerRoute(name: "NewsRss",
            pattern: "news/rss/{languageId:min(0)}",
            defaults: new { controller = "News", action = "ListRss" });

        endpointRouteBuilder.MapControllerRoute(name: "NewsItemEdit",
            pattern: "Admin/News/Edit/{id:min(0)?}",
            defaults: new { controller = "NewsAdmin", action = "NewsItemEdit", area = AreaNames.ADMIN });
    }
}
