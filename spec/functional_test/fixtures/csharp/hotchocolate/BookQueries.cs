using HotChocolate.Types;

namespace BookStore;

[ExtendObjectType(typeof(Query))]
public class BookQueries
{
    public Author GetAuthorById([ID] int authorId, AuthorService authors) => authors.Find(authorId);
}

[ExtendObjectType(OperationTypeNames.Mutation)]
public class AuthorMutations
{
    public Author RenameAuthor(int authorId, string name) => new Author(authorId, name);
}

// Extends an object type, not a root: contributes no root fields.
[ExtendObjectType(typeof(Book))]
public class BookExtensions
{
    public string GetIsbn([Parent] Book book) => book.Isbn;
}
