package tutorial;

import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

// A tutorial's servlet that happens to be called `Test`: a served route, not a JUnit class.
@WebServlet("/test")
public class Test extends HttpServlet {
    protected void doGet(HttpServletRequest req, HttpServletResponse resp) {
        String q = req.getParameter("q");
    }
}
