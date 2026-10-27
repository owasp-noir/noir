namespace Web.Infrastructure;

public class BaseRouteProvider
{
    // `{lang}` is a language-code segment only when SEO language URLs are on.
    protected string GetLanguageRoutePattern()
    {
        if (LocalizationSettings.SeoFriendlyUrlsForLanguagesEnabled)
        {
            return $"{{{RouteValues.Language}:maxlength(2)}}";
        }

        return string.Empty;
    }
}

public static class RouteValues
{
    public static string Language => "language";

    public static string SeName => "SeName";
}

public static class AreaNames
{
    public const string ADMIN = "Admin";
}
