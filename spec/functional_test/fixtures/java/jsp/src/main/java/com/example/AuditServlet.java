package com.example;

import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

@WebServlet("/audit")
public class AuditServlet extends HttpServlet {
  protected void doGet(HttpServletRequest req, HttpServletResponse resp) {
    req.getParameter("auditId");
    req.getHeader("X-Audit-Token");
  }

  protected void doPost(final HttpServletRequest httpRequest, HttpServletResponse resp) {
    httpRequest.getParameter("note");
    httpRequest.getCookies();
  }
}
