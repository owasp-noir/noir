<%
' Included fragment: never requested directly, so it must not become an
' endpoint even though it reads the request.
dim theme : theme = Request.QueryString("theme")
%>
