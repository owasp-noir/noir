using ServiceStack;

namespace ServiceStackDemo.Tests
{
    [Route("/test-only", "GET")]
    public class TestOnlyRequest : IReturn<TestOnlyResponse>
    {
        public string Name { get; set; } = "";
    }

    public class TestOnlyResponse
    {
        public string Result { get; set; } = "";
    }
}
