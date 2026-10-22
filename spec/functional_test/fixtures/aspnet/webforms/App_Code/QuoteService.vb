Imports System.Web.Services

Public Class QuoteService
    Inherits System.Web.Services.WebService

    <WebMethod(EnableSession:=True)> _
    Public Function GetQuote(ByVal symbol As String, ByVal count As Integer) As String
        Return symbol
    End Function

    <WebMethod()>
    Public Function Ping() As String
        Return "pong"
    End Function
End Class
