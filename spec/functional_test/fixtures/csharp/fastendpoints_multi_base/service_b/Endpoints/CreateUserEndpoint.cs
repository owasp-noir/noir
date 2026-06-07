using FastEndpoints;

public class CreateRequest
{
    public string Email { get; set; }
}

public class CreateUserEndpoint : Endpoint<CreateRequest>
{
    public override void Configure()
    {
        Post("/b/users");
    }
}
