using Wolverine.Http;
using Microsoft.AspNetCore.Authorization;

namespace Shapes.Wolv;

public static class OrderEndpoints
{
    // W1: plain
    [WolverineGet("/orders/{id}")]
    public static Order Get(int id) => new Order();

    // W2: string spelling an attribute
    private const string Help = """
        [WolverinePost("/phantom")]
        """;

    // W3: [Authorize] then verb in one list
    [Authorize, WolverinePost("/orders")]
    public static Order Create(CreateOrder cmd) => new Order();

    // W4: verb attribute split over lines
    [WolverineDelete(
        "/orders/{id}")]
    public static void Delete(int id) { }

    // W5: commented-out
    // [WolverinePut("/ghost")]
    /* [WolverinePatch("/ghost2")] */
    [WolverineGet("/orders")]
    public static Order[] List(string? status = "a,b") => [];
}

public class Order { }
public record CreateOrder(string Item);
