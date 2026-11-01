using Carter;

namespace Shapes.Carter;

// R1: base list on the next line
public class BooksModule
    : ICarterModule
{
    public void AddRoutes(IEndpointRouteBuilder app)
    {
        app.MapGet("/books", () => "{");
    }
}

// R2: CarterModule base path, ctor split over lines
public class AuthorsModule : CarterModule
{
    public AuthorsModule()
        : base("/authors")
    {
    }

    public override void AddRoutes(IEndpointRouteBuilder app)
    {
        app.MapGet("/{id}", (int id) => id);
    }
}

// R3: a string mentioning a module class
public class Notes
{
    private const string Doc = "class Fake : ICarterModule { }";
}
