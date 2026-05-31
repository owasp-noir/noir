<%
    // Application-set attribute — a real, user-meaningful parameter.
    Object userId = request.getAttribute("userId");

    // Container-managed attributes — populated by the servlet engine,
    // never by user input. These must NOT surface as parameters.
    Object sessionId = request.getAttribute("javax.servlet.request.ssl_session_id");
    Object certs = request.getAttribute("jakarta.servlet.request.X509Certificate");
%>
