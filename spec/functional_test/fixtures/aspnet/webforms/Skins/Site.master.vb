Partial Class Skins_Site
    Inherits System.Web.UI.MasterPage

    Protected Sub Page_Load(ByVal sender As Object, ByVal e As EventArgs)
        Dim width As String = Request.Cookies("menuwidth").Value
    End Sub
End Class
