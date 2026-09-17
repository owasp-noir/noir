using Microsoft.AspNetCore.Mvc;

[NonController]
[Route("excluded")]
public class ExcludedController : ControllerBase
{
    [HttpGet]
    public IActionResult Read() => Ok();
}

[ApiController]
[Route("internal")]
internal class InternalController : ControllerBase
{
    [HttpGet]
    public IActionResult Read() => Ok();
}

[Route("abstract")]
public abstract class AbstractController : ControllerBase
{
    [HttpGet]
    public IActionResult Read() => Ok();
}

[Route("generic")]
public class GenericController<T> : ControllerBase
{
    [HttpGet]
    public IActionResult Read() => Ok();
}

public class Container
{
    [Route("nested")]
    public class NestedController : ControllerBase
    {
        [HttpGet]
        public IActionResult Read() => Ok();
    }
}
