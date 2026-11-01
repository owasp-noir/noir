using System;
using Microsoft.AspNetCore.Mvc.Routing;

namespace Fx.A
{
    public class ApiRouteAttribute : Attribute, IRouteTemplateProvider
    {
        public ApiRouteAttribute(string resource)
        {
            Template = $"alpha/{resource}";
        }

        public string Template { get; }
        public int? Order => null;
        public string Name { get; }
    }
}
