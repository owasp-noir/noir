<%@LANGUAGE="VBSCRIPT" CODEPAGE="65001"%>
<!-- #include file="includes/header.asp"-->
<%
' A commented-out read must not surface:
'   sOld = Request.QueryString("legacy_id")
dim page : page = Request.QueryString("page")
dim sort : sort = Request.QueryString ("sort")
%>
<html><body>
<p>Page <%= Request.QueryString("page") %></p>
<script>
  // Client-side only: must not be read as server code.
  var q = Request.QueryString("clientside");
</script>
</body></html>
