using Microsoft.AspNetCore.Mvc;

public abstract class ApplicationEndpoint : ControllerBase
{
}

[Controller]
public abstract class MarkedEndpoint
{
}

public class UnmarkedController
{
}

[NonController]
public abstract class DisabledEndpoint : ControllerBase
{
}
