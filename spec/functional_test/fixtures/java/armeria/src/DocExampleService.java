package org.apache.skywalking.oap.server.webapp;

import com.linecorp.armeria.server.HttpService;
import com.linecorp.armeria.server.Server;
import com.linecorp.armeria.server.healthcheck.HealthCheckService;

/**
 * Demonstrates that builder chains living inside documentation must not
 * be picked up as real routes. The block comment below shows example
 * wiring that should be ignored by the analyzer:
 *
 * <pre>{@code
 * Server.builder()
 *       .service("/doc-comment-route", new OapProxyService())
 *       .service("/api/comment-thrift", HealthCheckService.of())
 *       .build()
 *       .start();
 * }</pre>
 */
public class DocExampleService {
    // A Java text block carrying the same example must also be ignored.
    public static final String EXAMPLE = """
        Server.builder()
              .service("/doc-textblock-route", new OapProxyService())
              .build()
              .start();
        """;

    public static void main(String[] args) throws Exception {
        // The only real route in this file.
        Server
            .builder()
            .service("/real/ping", HealthCheckService.of())
            .build()
            .start()
            .join();
    }
}
