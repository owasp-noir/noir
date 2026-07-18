<%@ WebHandler Language="VB" Class="Image" %>
Imports System.Web
Public Class Image
    Implements IHttpHandler

    Public Sub ProcessRequest(ByVal context As HttpContext)
        ' Aliased receiver: a Request-anchored pattern would miss these.
        Dim req As HttpRequest = context.Request
        Dim path As String = req.QueryString("strFullPath")
        Dim size As String = req.QueryString("intSize")
    End Sub
End Class
