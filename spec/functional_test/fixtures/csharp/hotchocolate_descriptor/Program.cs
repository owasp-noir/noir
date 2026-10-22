using HotChocolate.Types;

var builder = WebApplication.CreateBuilder(args);

builder.Services
    .AddGraphQLServer()
    .AddQueryType<QueryType>()
    .AddMutationType<MutationType>();

var app = builder.Build();
app.MapGraphQL();
app.Run();

public class Query
{
    public Book GetBook(int id) => new Book(id);

    public string GetInternalNote() => "ignored by the descriptor";
}

public class QueryType : ObjectType<Query>
{
    protected override void Configure(IObjectTypeDescriptor<Query> descriptor)
    {
        descriptor.Field(f => f.GetBook(default));
        descriptor.Ignore(f => f.GetInternalNote());

        descriptor
            .Field("hello")
            .Argument("name", a => a.Type<StringType>())
            .Resolve(ctx => $"Hello {ctx.ArgumentValue<string>("name")}");
    }
}

public class Mutation
{
    public bool Ping() => true;

    public bool Unlisted() => true;
}

public class MutationType : ObjectType<Mutation>
{
    protected override void Configure(IObjectTypeDescriptor<Mutation> descriptor)
    {
        descriptor.BindFieldsExplicitly();
        descriptor.Field(f => f.Ping());
    }
}
