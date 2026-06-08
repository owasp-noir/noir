package com.example;

import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

public class SharedServlet extends HttpServlet {
    protected void doGet(HttpServletRequest request, HttpServletResponse response) {
        request.getParameter("a");
    }
}
