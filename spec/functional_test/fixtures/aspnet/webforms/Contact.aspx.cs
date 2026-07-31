using System;
using System.Web;

public partial class Contact : System.Web.UI.Page
{
    protected void Page_Load(object sender, EventArgs e)
    {
        string topic = Request.QueryString["topic"];
    }
}
