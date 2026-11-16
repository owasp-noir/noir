package demo;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.core.Response;

// A client stub: no class implements it, so it serves nothing.
@Path("/invoices")
public interface BillingClient {
    @GET
    Response invoices();
}
