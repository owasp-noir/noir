Partial Class Controls_Search
    Inherits System.Web.UI.UserControl

    Protected Sub Page_Load(ByVal sender As Object, ByVal e As EventArgs)
        ' Most real reads live in user controls, which are not routable
        ' themselves - they belong to the pages that register them.
        Dim term As String = Request.QueryString("q")
        Dim page As String = Request.Form("pageNo")
    End Sub
End Class
