Imports System.Web.Mvc

Public Class AdminAreaRegistration
    Inherits AreaRegistration

    Public Overrides Sub RegisterArea(ByVal context As AreaRegistrationContext)
        context.MapRoute(
            "Admin_default",
            "Admin/{controller}/{action}/{id}",
            New With {.action = "Index", .id = UrlParameter.Optional}
        )
    End Sub
End Class
