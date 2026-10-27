namespace App.Infrastructure
{
    public static class RouteExtensions
    {
        static string Lang()
        {
            if (Settings.SeoUrls)
                return "{lang}";
            else
                return "en";
        }

        static void Other()
        {
            var tpl = "wrong/{action}";
        }

        // None of these templates can be read: each is skipped.
        public static void UseMoreRoutes(this IEndpointRouteBuilder app, string tpl)
        {
            app.MapControllerRoute(name: "param", pattern: tpl, defaults: new { controller = "Tools", action = "Details" });
            app.MapControllerRoute(name: "branches", pattern: $"{Lang()}/c", defaults: new { controller = "Tools", action = "Details" });
            app.MapControllerRoute(name: "concat", pattern: $"pre/{Zone}/" + "post", defaults: new { controller = "Tools", action = "Details" });
        }

        const string Zone = "zone";
    }
}
