<%
    String q = request . getParameter ( 'q' );
    String[] tags = request.getParameterValues("tag");
    Object mode = request.getAttribute('mode');
    String trace = request.getHeader('X-Trace');
%>
${param['sort']}
${paramValues.category}
${cookie.session_id.value}

<form action="${pageContext.request.contextPath}/login" method="post">
    <input type="text" name="username" />
    <input type="password" name="password" />
    <input type="hidden" name="csrf" />
</form>

<form method="get" action="/reports/search">
    <input name="q" />
    <select name="status"></select>
</form>

<form action="https://example.com/external" method="post">
    <input name="ignored" />
</form>
