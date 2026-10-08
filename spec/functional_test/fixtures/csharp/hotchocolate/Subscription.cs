using HotChocolate;
using HotChocolate.Types;

namespace BookStore;

public class Subscription
{
    [Subscribe]
    [Topic]
    public Book OnBookAdded([EventMessage] Book book) => book;

    [Subscribe]
    [Topic("{" + nameof(authorId) + "}")]
    public Book OnAuthorBookAdded(int authorId, [EventMessage] Book book) => book;

    // The stream named by `With` is the subscribe resolver, not a field.
    public async IAsyncEnumerable<Book> ReviewStream([Service] ITopicEventReceiver receiver)
    {
        yield break;
    }

    [Subscribe(With = nameof(ReviewStream))]
    public Book OnReview([EventMessage] Book book) => book;
}
