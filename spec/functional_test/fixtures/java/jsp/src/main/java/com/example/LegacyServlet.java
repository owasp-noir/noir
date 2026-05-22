package com.example;

import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

public class LegacyServlet extends HttpServlet {
  protected void doPost(HttpServletRequest request, HttpServletResponse response) {
    request.getParameter("legacyId");
  }
}
