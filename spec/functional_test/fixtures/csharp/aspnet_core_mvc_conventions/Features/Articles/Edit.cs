namespace App.Features.Articles;

public class Edit
{
    public record Model(Create.ArticleData Article);
    public record Command(Model Model, string Slug);
}
