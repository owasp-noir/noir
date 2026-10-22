<%
If Request.ServerVariables("REQUEST_METHOD") = "POST" Then
    dim user : user = Request.Form("username")
    dim pass : pass = Request.Form ("password")
    ' An apostrophe inside a string is not a comment:
    Response.Write "<a onclick=""alert('hi')"">go</a>"
End If
dim token : token = Request.Cookies("session")
dim fwd : fwd = Request.ServerVariables("HTTP_X_FORWARDED_FOR")
%>
