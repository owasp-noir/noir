package com.example;

import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

// A `/*` inside the URL pattern string must not open a comment, a trailing
// `//` comment must not hide the annotation, and a commented-out
// annotation is not a servlet.
// @WebServlet("/files-legacy")
@WebServlet("/files/*") // file browser
public class FilesServlet extends HttpServlet {
  /** Reads one file. */
  protected void doGet(HttpServletRequest req, HttpServletResponse resp) {
    req.getParameter("name");
  }
}
