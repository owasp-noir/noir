using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;

public class Warehouse { }

public static class InventoryRoutes
{
    public static IResult Update([AsParameters] InventoryInputs inputs, Warehouse warehouse,
        ItemCode code, SessionSelection selection, [FromBody] StockChange change, [AsParameters] Window window) => Results.Ok(inputs);

    public static IResult Status(Warehouse warehouse, HttpContext context,
        CancellationToken cancellation, [FromServices] TimeProvider clock) => Results.Ok();
}

public record InventoryInputs([property: FromHeader(Name = "X-Store")] string Store,
    [FromQuery(Name = "filter")] string Term, int id, Warehouse Warehouse);

public record ItemCode(string Value)
{
    public static bool TryParse(string text, out ItemCode result)
    {
        result = new ItemCode(text);
        return true;
    }
}

public record SessionSelection(string? Session)
{
    public static ValueTask<SessionSelection> BindAsync(HttpContext context) =>
        ValueTask.FromResult(new SessionSelection(context.Request.Cookies["session"]));
}

public record StockChange(int Id);
public class Window([FromQuery(Name = "since")] int start)
{
    public int Start { get; } = start;
    public static int Maximum { get; set; }
    public string Label => "current";
}
