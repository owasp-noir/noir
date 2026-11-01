using System;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Routing;

namespace Fx.Http
{
    public class VersionedApiControllerAttribute : Attribute, IRouteTemplateProvider
    {
        public const string CONTROLLER_RESOURCE = "[controller]";

        public VersionedApiControllerAttribute(int version, string resource = CONTROLLER_RESOURCE)
        {
            Template = $"api/v{version}/{resource}";
        }

        public string Template { get; }
        public int? Order => 2;
        public string Name { get; set; }
    }

    public class V3ApiControllerAttribute : VersionedApiControllerAttribute
    {
        public V3ApiControllerAttribute(string resource = "[controller]")
            : base(3, resource)
        {
        }
    }

    public class V5ApiControllerAttribute : VersionedApiControllerAttribute
    {
        public V5ApiControllerAttribute(string resource = "[controller]")
            : base(5, resource)
        {
        }
    }

    [AttributeUsage(AttributeTargets.Method)]
    public class RestGetByIdAttribute : Attribute, IActionHttpMethodProvider, IRouteTemplateProvider
    {
        public IEnumerable<string> HttpMethods => new[] { "GET" };
        public string Template => "{id:int}";
        public int? Order => 0;
        public string Name { get; }
    }

    [AttributeUsage(AttributeTargets.Method)]
    public class RestPutByIdAttribute : HttpPutAttribute
    {
        public RestPutByIdAttribute()
            : base("{id:int?}")
        {
        }
    }

    [AttributeUsage(AttributeTargets.Method)]
    public class RestPostByIdAttribute : HttpPostAttribute
    {
    }

    // Not a route attribute: a plain marker with a Template property.
    public class LabelAttribute : Attribute
    {
        public string Template => "labelled";
    }
}
