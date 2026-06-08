using FastEndpoints;

public class CreateRequest
{
    public string Name { get; set; }
}

public class CreateUserEndpoint : Endpoint<CreateRequest>
{
    public override void Configure()
    {
        Post("/a/users");
    }
}
