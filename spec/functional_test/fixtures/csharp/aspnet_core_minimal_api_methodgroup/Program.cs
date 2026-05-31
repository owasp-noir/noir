using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Routing;

var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

// Method-group handler: route lives on the Map line, parameters and body
// live in the referenced method. The analyzer resolves it for both.
app.MapGet("/products", GetProducts)
   .WithName("ListProducts")
   .Produces<IResult>();

app.MapGet("/products/{id:int}", GetProductById);
app.MapPost("/products", CreateProduct);

// [AsParameters] bundle whose type is declared in this file: the query/
// header members expand, the injected service member is dropped.
app.MapGet("/search", Search);

// Services injected straight into a lambda are not request parameters.
app.MapGet("/inventory", (IProductRepository repository, AppDbContext db, ILogger<Program> logger) =>
{
    return Results.Ok(repository.All());
});

app.MapPost("/orders", ([FromHeader(Name = "x-request-id")] Guid requestId, CreateOrderRequest order, ISender sender) =>
{
    sender.Send(order);
    return Results.Accepted();
});

app.Run();

static IResult GetProducts(IProductRepository repository, int? page, [FromQuery] string? sort)
{
    var items = repository.Query(page, sort);
    return Results.Ok(items);
}

static IResult GetProductById([FromServices] IProductRepository repository, int id)
{
    var item = repository.Find(id);
    return Results.Ok(item);
}

static IResult CreateProduct(CreateProductRequest request, IProductRepository repository)
{
    repository.Add(request);
    return Results.Created($"/products/{request.Name}", request);
}

static IResult Search([AsParameters] ProductSearch query, IProductRepository repository)
{
    return Results.Ok(repository.Search(query));
}

record CreateOrderRequest(string Sku, int Quantity);
record CreateProductRequest(string Name, decimal Price);

class ProductSearch
{
    public string? Term { get; set; }
    public int Page { get; set; }

    [FromHeader(Name = "X-Tenant")]
    public string? Tenant { get; set; }

    public IProductRepository? Repository { get; set; }
}
