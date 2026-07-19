using System;
using System.Web;

public partial class BugTest : System.Web.UI.Page
{
    protected void Page_Load(object sender, EventArgs e)
    {
        string a = "escaped \" // dummy"; string b = Request.QueryString["RealParam"];
    }
}
