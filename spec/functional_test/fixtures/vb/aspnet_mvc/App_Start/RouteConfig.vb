Imports System.Web.Mvc
Imports System.Web.Routing

Public Module RouteConfig
    Public Sub RegisterRoutes(ByVal routes As RouteCollection)
        routes.IgnoreRoute("{resource}.axd/{*pathInfo}")

        ' routes.MapRoute("Old", "old-route")
        routes.MapRoute("About", "about-us", New With {.controller = "Home", .action = "About"})

        routes.MapRoute( _
            name:="Default", _
            url:="{Controller}/{Action}/{id}", _
            defaults:=New With {.controller = "Home", .action = "Index", .id = UrlParameter.Optional} _
        )
    End Sub
End Module
