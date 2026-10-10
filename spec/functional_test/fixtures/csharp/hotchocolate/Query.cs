using HotChocolate;
using HotChocolate.Types;

namespace BookStore;

public class Query
{
    // GetBook -> book; id is an argument, the repository is injected.
    public Book GetBook(int id, IBookRepository repository) => repository.Find(id);

    // Async suffix is dropped because the method returns a Task.
    [UsePaging]
    [UseFiltering]
    public async Task<IEnumerable<Book>> GetBooksAsync(
        string? title,
        [Service] BookService service,
        CancellationToken cancellationToken)
    {
        return await service.Search(title, cancellationToken);
    }

    [GraphQLName("whoAmI")] // exposed name
    public string CurrentUser(ClaimsPrincipal user, [GraphQLName("verbose")] bool includeRoles) => user.Identity!.Name!;

    public string Version => "1.0";

    public string APIStatus { get; } = "ok";

    [GraphQLIgnore] // internal only
    public string Secret() => "hidden";

    public static string StaticHelper() => "not bound";

    public void Reset() { }

    public override string ToString() => "Query";

    private string Internal() => "private";
}

// Not registered as a root and carries no HotChocolate marker.
public class ReportQuery
{
    public string GetReport(int id) => "report";
}
