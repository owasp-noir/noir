using Microsoft.AspNetCore.Mvc;

[ApiController]
[Route("catalog")]
public class Catalog : ControllerBase
{
    [HttpGet]
    public IActionResult List() => Ok();
}

[Controller]
[Route("status")]
public class Status
{
    [HttpGet]
    public string Read() => "ready";
}

[Route("named")]
public class NamedController
{
    [HttpGet]
    public string Read() => "ready";
}

[Route("helper")]
public class Helper
{
    [HttpGet]
    public string Read() => "not a controller";
}
