<%@ page import="org.json.simple.JSONObject" %>
<%@ page import="org.json.simple.parser.JSONParser" %>
<%@ page import="java.io.*" %>
<%
    Reader reader = new InputStreamReader(request.getInputStream(), "UTF-8");
    JSONObject jsonObject = (JSONObject) new JSONParser().parse(reader);
    String secret = (String) jsonObject.get("secret");
    String orderId = (String) jsonObject.get("orderId");
%>
