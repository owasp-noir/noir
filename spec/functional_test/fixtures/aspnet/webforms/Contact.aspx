<%@ Page Language="C#" CodeBehind="Contact.aspx.cs" Inherits="Contact" %>
<html>
<body>
    <!-- A server-side form is what makes the page a POST target; the
         code-behind reads only the query string. -->
    <form id="frmContact" runat="server">
        <asp:TextBox runat="server" ID="txtMessage" />
        <asp:Button runat="server" ID="btnSend" Text="Send" />
    </form>
</body>
</html>
