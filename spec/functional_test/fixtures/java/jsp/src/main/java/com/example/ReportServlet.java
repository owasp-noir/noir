package com.example;

import jakarta.servlet.annotation.WebInitParam;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

// Regression guard: `initParams` nests `@WebInitParam(value="...")`, whose
// `value=` is an init-param value, NOT a URL pattern. Only `/reports/*` and
// `/api/reports` are routes — `json` / `Not provided` must not surface.
@WebServlet(
    name = "ReportServlet",
    urlPatterns = {"/reports/*", "/api/reports"},
    initParams = {
      @WebInitParam(name = "format", value = "json"),
      @WebInitParam(name = "fallback", value = "Not provided")
    })
public class ReportServlet extends HttpServlet {
  protected void doGet(HttpServletRequest request, HttpServletResponse response) {
    request.getParameter("reportId");
    request.getHeader("X-Report-Token");
  }

  protected void doPost(HttpServletRequest request, HttpServletResponse response) {
    request.getParameter("title");
  }
}
