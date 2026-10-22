using ServiceStack;

namespace ServiceStackDemo.ServiceModel
{
    // DTO declared on the attribute's own line.
    [Route("/same")] public class SameLine : IReturn<string> { public string A { get; set; } }

    // Named Verbs property; Summary is not a verb list, and its "(" is text.
    [Route("/verbs", Verbs = "GET", Summary = "List (all)")]
    public class VerbsNamed : IReturn<string>
    {
        public string B { get; set; }
    }

    // Several Route(...) entries in one attribute list.
    [Route("/two1"), Route("/two2", "PUT")]
    public class Two : IReturn<string>
    {
        public string C { get; set; }
    }

    // An attribute list spread across lines.
    [Route(
        "/multi",
        "POST")]
    public class Multi : IReturn<string>
    {
        public string D { get; set; }
    }
}
