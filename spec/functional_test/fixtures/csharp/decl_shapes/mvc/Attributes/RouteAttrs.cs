using System;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Routing;

namespace Shapes.Attributes;

// C1: a project route attribute with a constructor + base call
public class V1ApiAttribute : RouteAttribute
{
    public V1ApiAttribute(string resource = "")
        : base("api/v1/" + resource) { }
}

public class VersionedApiAttribute : Attribute, IRouteTemplateProvider
{
    public VersionedApiAttribute(string resource, int version = 1)
    {
        Template = $"api/v{version}/{resource}";
    }
    public string Template { get; }
    public int? Order => 2;
    public string Name { get; set; }
}

// C2: a filter attribute with a Template property (not a route)
public class AuditAttribute : Attribute
{
    public string Template { get; set; } = "audit/{x}";
}

public class GetByIdAttribute : HttpGetAttribute
{
    public GetByIdAttribute() : base("{id:int}") { }
}
