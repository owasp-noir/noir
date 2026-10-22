using HotChocolate.Types;

namespace BookStore;

// Source-generator style: every [QueryType] class merges into Query.
[QueryType]
public static partial class AuthorQueries
{
    public static IQueryable<Author> GetAuthors(ApplicationDbContext db) => db.Authors;

    public static async Task<Author?> GetAuthorByNameAsync(
        string name,
        IAuthorByNameDataLoader loader,
        ISelection selection,
        CancellationToken ct)
        => await loader.LoadAsync(name, ct);
}

[MutationType]
public static class AuthorUploads
{
    public static Task<string> UploadPhotoAsync(int authorId, IFile photo) => Task.FromResult(photo.Name);
}
