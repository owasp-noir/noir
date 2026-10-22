<%
' Bare Request() is ambiguous - IIS searches QueryString then Form.
dim term : term = Request("q")
' Runtime-built keys are unresolvable and must be skipped:
dim dyn : dyn = Request("prefix-" & userId)
dim raw : raw = Request.QueryString( _
    "page")
%>
