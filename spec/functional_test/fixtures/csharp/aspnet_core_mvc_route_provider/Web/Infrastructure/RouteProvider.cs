using Microsoft.AspNetCore.Routing;

namespace Web.Infrastructure;

public class RouteProvider : BaseRouteProvider, IRouteProvider
{
    public void RegisterRoutes(IEndpointRouteBuilder endpointRouteBuilder)
    {
        var lang = GetLanguageRoutePattern();

        endpointRouteBuilder.MapControllerRoute(name: "areaRoute",
            pattern: $"{{area:exists}}/{{controller=Home}}/{{action=Index}}/{{id?}}");

        endpointRouteBuilder.MapControllerRoute(name: "Login",
            pattern: $"{lang}/login/",
            defaults: new { controller = "Customer", action = "Login" });

        endpointRouteBuilder.MapControllerRoute("CustomerAddressDelete",
            "customer/addressdelete",
            new { controller = "Customer", action = "AddressDelete" });

        endpointRouteBuilder.MapControllerRoute(name: "OrderPdf",
            pattern: $"orderdetails/pdf/{{orderId:min(0)}}",
            defaults: new { controller = "Order", action = "GetPdfInvoice" });

        var genericPattern = $"{lang}/{{{RouteValues.SeName}}}";
        endpointRouteBuilder.MapControllerRoute(name: "Product",
            pattern: genericPattern,
            defaults: new { controller = "Product", action = "ProductDetails" });

        // A template read from configuration cannot be resolved: skipped.
        endpointRouteBuilder.MapControllerRoute(name: "Configured",
            pattern: Configuration["Routes:Search"],
            defaults: new { controller = "Product", action = "Search" });

        endpointRouteBuilder.MapControllerRoute(name: "Default",
            pattern: "{controller=Home}/{action=Index}/{id?}");
    }
}
