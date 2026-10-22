using ServiceStack;

namespace ServiceStackDemo.ServiceModel
{
    // Attribute-routed request DTO: two [Route] attributes, both GET, so
    // /hello and /hello/{Name} each answer independently.
    [Route("/hello", "GET")]
    [Route("/hello/{Name}", "GET")]
    public class Hello : IReturn<HelloResponse>
    {
        public string? Name { get; set; }
    }

    public class HelloResponse
    {
        public string Result { get; set; } = "";
    }
}
