using System;
using Microsoft.AspNetCore.Mvc.Routing;

namespace Fx.B
{
    public class ApiRouteAttribute : Attribute, IRouteTemplateProvider
    {
        public ApiRouteAttribute(string resource)
        {
            Template = $"beta/{resource}";
        }

        public string Template { get; }
        public int? Order => null;
        public string Name { get; }
    }
}
