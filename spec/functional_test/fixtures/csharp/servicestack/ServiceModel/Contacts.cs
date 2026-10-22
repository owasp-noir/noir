using ServiceStack;

namespace ServiceStackDemo.ServiceModel
{
    // No [Route] attribute here on purpose: this DTO is only wired to a path
    // through the fluent Routes.Add<GetContact>(...) call in AppHost.cs, so
    // resolving its properties needs the cross-file type index.
    public class GetContact : IReturn<GetContactResponse>
    {
        public string ContactId { get; set; } = "";
    }

    public class GetContactResponse
    {
        public string Name { get; set; } = "";
    }
}
