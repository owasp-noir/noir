using Marten;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Wolverine;
using Wolverine.Http;

namespace OrderApi;

public static class OrderEndpoints
{
    [WolverinePost("/orders")]
    public static (OrderCreated, OrderPlaced) Post(CreateOrder command, IDocumentSession session) => (new(1), new());

    [WolverineGet("/orders/{id}")]
    public static Order Get(int id, IQuerySession session) => new();

    [WolverineGet("orders")]
    public static Task<IReadOnlyList<Order>> Search(string? customer, int page, [FromHeader(Name = "X-Tenant")] string tenant, IQuerySession session, CancellationToken token)
        => session.Query<Order>().ToListAsync(token);

    [Authorize]
    [WolverinePut("/orders/{id:guid}/ship")]
    public static async Task Ship(Guid id, ShipOrder command, IMessageBus bus)
    {
        await bus.PublishAsync(command);
    }

    [WolverineDelete("/orders/{id}")]
    public static void Delete([Document] Order order, IDocumentSession session) => session.Delete(order);

    [WolverinePatch("/orders/{id}/note")]
    public static void Note (int id, [FromQuery(Name = "reason")] string why, NotePatch patch) { }

    // An attribute list split over several lines.
    [WolverinePost("/orders/{id}/refund",
        Name = "RefundOrder")]
    public static void Refund(int id, RefundOrder command) { }

    [AllowAnonymous, WolverineGet("/orders/{id}/receipt")]
    public static string Receipt(int id) => "receipt";

    // [WolverineGet("/ghost")]
    // public static string Ghost() => "commented out";
}

public class OrderStatusEndpoint
{
    [AllowAnonymous]
    [WolverineHead("/status")]
    public string Head() => "ok";
}
