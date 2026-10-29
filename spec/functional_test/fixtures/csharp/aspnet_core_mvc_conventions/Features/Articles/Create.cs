namespace App.Features.Articles;

public class Create
{
    public class ArticleData
    {
        public string? Title { get; init; }
        public string? Body { get; init; }
    }

    public record Command(ArticleData Article);
}
