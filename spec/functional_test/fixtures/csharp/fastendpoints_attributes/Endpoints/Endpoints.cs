using FastEndpoints;

namespace App.Endpoints;

// Endpoint configuration with attributes: no Configure() override.
[HttpPost("/f01/address")]
[Authorize(Roles = "Admin,Manager")]
public class UpdateAddress : Endpoint<AddressRequest, AddressResponse>
{
    public override Task HandleAsync(AddressRequest req, CancellationToken ct) => Task.CompletedTask;
}

[HttpGet("/f02/address/{id}"), AllowAnonymous]
public class GetAddress : EndpointWithoutRequest<AddressResponse>
{
    public override Task HandleAsync(CancellationToken ct) => Task.CompletedTask;
}

// Fluent generics: Ep.Req<T>.Res<T> / Ep.NoReq.Res<T> bases.
public class CreateAddress : Ep.Req<AddressRequest>.Res<AddressResponse>
{
    public override void Configure()
    {
        Post("/f03/address");
    }
    public override Task HandleAsync(AddressRequest req, CancellationToken ct) => Task.CompletedTask;
}

public class ListAddresses : Ep.NoReq.Res<AddressResponse>
{
    public override void Configure() => Get("/f04/addresses");
    public override Task HandleAsync(CancellationToken ct) => Task.CompletedTask;
}

// Classic shape.
public class DeleteAddress : Endpoint<AddressRequest>
{
    public override void Configure()
    {
        Delete("/f05/address/{Id}");
    }
    public override Task HandleAsync(AddressRequest req, CancellationToken ct) => Task.CompletedTask;
}

// Route held in a constant.
public class SearchAddress : EndpointWithoutRequest
{
    private const string Route = "/f06/address/search";
    public override void Configure()
    {
        Get(Route);
    }
    public override Task HandleAsync(CancellationToken ct) => Task.CompletedTask;
}

// Expression-bodied Configure on a classic base.
public class PingAddress : EndpointWithoutRequest
{
    public override void Configure() => Get("/f07/address/ping");
    public override Task HandleAsync(CancellationToken ct) => Task.CompletedTask;
}

public class AddressRequest
{
    public int Id { get; set; }
    public string Street { get; set; } = "";
}

public class AddressResponse { public string Street { get; set; } = ""; }
