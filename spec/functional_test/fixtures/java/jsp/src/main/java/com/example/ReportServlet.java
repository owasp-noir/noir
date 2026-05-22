package com.example;

import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

@WebServlet(name = "ReportServlet", urlPatterns = {"/reports/*", "/api/reports"})
public class ReportServlet extends HttpServlet {
  protected void doGet(HttpServletRequest request, HttpServletResponse response) {
    request.getParameter("reportId");
    request.getHeader("X-Report-Token");
  }

  protected void doPost(HttpServletRequest request, HttpServletResponse response) {
    request.getParameter("title");
  }
}
