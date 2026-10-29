package demo;

import org.eclipse.jetty.ee10.servlet.ServletContextHandler;
import org.eclipse.jetty.ee10.servlet.ServletHolder;
import org.glassfish.jersey.server.ResourceConfig;
import org.glassfish.jersey.servlet.ServletContainer;

public class Main {
    static ServletContextHandler context() {
        final var context = new ServletContextHandler();
        final var api = new ResourceConfig();
        api.packages("demo.api");
        final var admin = new ResourceConfig();
        admin.packages("demo.admin");

        // One holder variable, reassigned: each mount uses the value it has there.
        ServletHolder holder = new ServletHolder(new ServletContainer(api));
        context.addServlet(holder, "/api/*");
        holder = new ServletHolder(new ServletContainer(admin));
        context.addServlet(holder, "/admin/*");
        return context;
    }
}
