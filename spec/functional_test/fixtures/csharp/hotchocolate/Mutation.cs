using HotChocolate;
using HotChocolate.Subscriptions;

namespace BookStore;

public class Mutation
{
    // Mutation conventions fold the arguments into one `input` argument.
    public async Task<Book> AddBookAsync(
        string title,
        int authorId,
        ITopicEventSender sender,
        CancellationToken cancellationToken)
    {
        var book = new Book(title, authorId);
        await sender.SendAsync(nameof(Subscription.OnBookAdded), book, cancellationToken);
        return book;
    }

    // Already takes its `<Name>Input` type, so the convention leaves it.
    public Book UpdateBook(UpdateBookInput input) => new Book(input.Title, input.AuthorId);

    public bool ClearCache() => true;
}

public record UpdateBookInput(string Title, int AuthorId);
