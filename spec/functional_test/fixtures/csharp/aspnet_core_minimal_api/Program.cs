using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Routing;

var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

app.MapGet("/users", () => Results.Ok());
app.MapGet("/users/{id:int}", (int id) => Results.Ok(id));
app.MapPost("/users", (CreateUserRequest req) => Results.Created($"/users/{req.Name}", req));
app.MapPut("/users/{id}", (int id, UpdateUserRequest req) => Results.Ok(req));
app.MapDelete("/users/{id}", ([FromRoute] int id, [FromQuery] bool soft) => Results.NoContent());
app.MapPatch("/users/{id}", async (HttpContext context) =>
{
    var trace = context.Request.Headers["X-Trace-Id"];
    var sessionId = context.Request.Cookies["sid"];
    await context.Response.WriteAsync($"{trace}:{sessionId}");
});

app.Map("/fallback", () => Results.Ok());
app.MapMethods("/bulk", new[] { HttpMethods.Put, "PATCH" }, () => Results.Ok());

var api = app.MapGroup("/api");
var v1 = api.MapGroup("/v1");
var nested = app.MapGroup("/nested").MapGroup("/v2");

v1.MapGet("/products/{sku}", ([FromRoute(Name = "sku")] string productSku, [FromHeader(Name = "X-Mode")] string mode) => Results.Ok());
nested.MapPost("/orders", ([FromBody] CreateOrderRequest order) => Results.Ok(order));
app.MapGroup("/inline").MapPost("/submit", (CreateUserRequest req) => Results.Ok(req));

app.Run();

record CreateUserRequest(string Name);
record UpdateUserRequest(string Name);
record CreateOrderRequest(string Id);
