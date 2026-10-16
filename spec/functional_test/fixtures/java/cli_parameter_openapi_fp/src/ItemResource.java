import io.swagger.v3.oas.annotations.Parameter;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;

// A JAX-RS resource documented with the swagger/OpenAPI `@Parameter`. It is
// not a JCommander class: the name-less `@Parameter(description = ...)` must
// not turn the next local declaration into a CLI "argument". The `new Options(`
// is an unrelated app class that still lets the file through the CLI gate.
@Path("/items")
public class ItemResource {
    @GET
    @Path("/{id}")
    public String get(@Parameter(description = "The item id", required = true) @PathParam("id") int id) {
        final Item item = ItemStore.lookup(id);
        Options options = new Options(true);
        return item.toString();
    }
}
