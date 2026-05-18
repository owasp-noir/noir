// Regression guard: anything under `/test/`, `/tests/`, or
// `/testassets/` is .NET test infrastructure (xUnit/NUnit/MSTest
// fixtures), never a real route handler. None of the URLs below
// should appear in the fixture's expected-endpoints list.
using Microsoft.AspNetCore.Mvc;

namespace MyApp.Test;

[ApiController]
[Route("[controller]")]
public class ShouldNotAppearControllerTests : ControllerBase
{
    [HttpGet("should-not-appear-test")]
    public string Get() => "";

    [HttpPost("should-not-appear-test")]
    public string Post() => "";
}
