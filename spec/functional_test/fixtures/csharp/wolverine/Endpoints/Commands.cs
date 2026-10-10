namespace OrderApi;

public record CreateOrder(string Customer, decimal Total, string[] Items);

public class ShipOrder
{
    public string Carrier { get; set; }
    public DateTime ShipBy { get; init; }
}

public record OrderCreated(int Id);
