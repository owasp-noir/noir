package demo;

import org.eclipse.jetty.ee10.servlet.ServletContextHandler;
import org.eclipse.jetty.ee10.servlet.ServletHolder;
import org.eclipse.jetty.server.Server;
import org.glassfish.jersey.server.ResourceConfig;
import org.glassfish.jersey.servlet.ServletContainer;

public class Main {
    public static void main(String[] args) throws Exception {
        final var server = new Server(8080);
        final var context = new ServletContextHandler();

        final var config = new ResourceConfig();
        config.packages("demo.resources");
        final var holder = new ServletHolder("api", new ServletContainer(config));
        context.addServlet(holder, "/api/*");

        server.setHandler(context);
        server.start();
    }
}
