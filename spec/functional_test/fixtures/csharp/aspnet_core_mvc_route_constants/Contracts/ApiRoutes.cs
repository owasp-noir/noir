namespace App.Contracts;

// The "ApiRoutes contract class" shape: every route template lives in one
// static class shared with the client SDK and the integration tests.
public static class ApiRoutes
{
    public const string Root = "api";
    public const string Version = "v1";
    public const string Base = Root + "/" + Version;

    public const string Health = "api/health";              // literal
    public const string Interp = $"{Root}/interp";           // interpolated constant
    public const string Concat = Root + "/concat";           // concatenated constant

    public static class Posts
    {
        public const string GetAll = Base + "/posts";
        public const string Get = Base + "/posts/{postId}";
        public const string Create = Base + "/posts";
        public const string Delete = $"{Base}/posts/{{postId}}";
    }
}
