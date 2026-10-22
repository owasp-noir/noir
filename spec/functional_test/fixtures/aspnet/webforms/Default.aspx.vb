Partial Class _Default
    Inherits System.Web.UI.Page

    Protected Sub Page_Load(ByVal sender As Object, ByVal e As EventArgs)
        ' Commented-out reads must not surface:
        '   Dim old As String = Request.QueryString("legacy")
        Dim id As String = Request.QueryString("CategoryID")
        Dim mode As String = Request("mode")
        ' Runtime-built keys are unresolvable:
        Dim dyn As String = Request("prefix-" & TabModuleId.ToString())
        ' Framework postback plumbing is not a user parameter:
        Dim ev As String = Request.Form("__EVENTTARGET")
    End Sub
End Class
