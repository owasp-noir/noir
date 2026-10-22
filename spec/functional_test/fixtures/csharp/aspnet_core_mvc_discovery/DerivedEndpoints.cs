using Microsoft.AspNetCore.Mvc;

[Route("inventory")]
public class Inventory : ApplicationEndpoint
{
    [HttpPost]
    public IActionResult Create() => Ok();
}

[Route("ping")]
public class Ping : MarkedEndpoint
{
    [HttpGet]
    public string Read() => "pong";
}

[Route("unmarked")]
public class Unmarked : UnmarkedController
{
    [HttpGet]
    public string Read() => "not a controller";
}

[Route("disabled")]
public class DisabledController : DisabledEndpoint
{
    [HttpGet]
    public string Read() => "not a controller";
}
