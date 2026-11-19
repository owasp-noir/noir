using Carter;

namespace App.Modules;

public class OrdersModule : CarterModule
{
    private const string BasePath = "/c10/orders";

    public OrdersModule() : base(BasePath) { }

    public override void AddRoutes(IEndpointRouteBuilder app)
    {
        app.MapGet("/{id}", (int id) => "x");
    }
}

public class StockModule() : CarterModule("/k04")
{
    public override void AddRoutes(IEndpointRouteBuilder app)
    {
        app.MapGet("/primary-ctor", () => "x");
    }
}

public class ItemsModule : ICarterModule
{
    private const string ItemsRoute = "/items/{id}";

    public void AddRoutes(IEndpointRouteBuilder app)
    {
        var group = app.MapGroup(Routes.Root);
        group.MapGet(ItemsRoute, (int id) => "x");
    }
}

public static class Routes
{
    public const string Root = "/catalog";
}
