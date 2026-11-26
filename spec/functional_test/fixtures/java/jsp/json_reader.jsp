<%@ page import="org.json.JSONObject" %>
<%@ page import="java.io.BufferedReader" %>
<%
    String signature = request.getHeader("X-Signature");
    BufferedReader br = request.getReader();
    StringBuilder sb = new StringBuilder();
    String line;
    while ((line = br.readLine()) != null) {
        sb.append(line);
    }
    JSONObject event = new JSONObject(sb.toString());
    String eventType = event.getString("eventType");
    int retry = event.optInt("retry", 0);
    JSONObject data = event.getJSONObject("data");
    String paymentId = data.getString("paymentId");
%>
