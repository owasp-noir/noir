Public Class HomeController
    Inherits System.Web.Mvc.Controller

    Function Index() As ActionResult
        Return View()
    End Function

    Function Details(ByVal id As Integer) As ActionResult
        Return View()
    End Function

    <HttpPost()>
    <ValidateAntiForgeryToken()>
    Function Contact(ByVal name As String, ByVal message As String) As ActionResult
        Return View()
    End Function

    <AcceptVerbs(HttpVerbs.Get Or HttpVerbs.Post)>
    Public Function Search(ByVal query As String) As ActionResult
        Return View()
    End Function

    <NonAction>
    Public Function BuildModel() As Object
        Return Nothing
    End Function

    Public Shared Function Util() As String
        Return ""
    End Function

    Protected Overrides Sub Dispose(ByVal disposing As Boolean)
        MyBase.Dispose(disposing)
    End Sub

    Private Class Nested
        Public Function NotAnAction() As String
            Return ""
        End Function
    End Class

    <HttpPost()>
    <ActionName("Delete")>
    Function DeleteConfirmed(ByVal id As Integer) As ActionResult
        Return RedirectToAction("Index")
    End Function

    Public Overrides Function ToString() As String
        Return "home"
    End Function

    Function About() As ActionResult
        Return View()
    End Function
End Class
