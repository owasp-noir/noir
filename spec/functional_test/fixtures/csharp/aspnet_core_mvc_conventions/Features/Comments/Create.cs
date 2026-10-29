namespace App.Features.Comments;

public class Create
{
    public record Model(string Body);
    public record Command(Model Model, string Slug);
}
