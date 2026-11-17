import com.beust.jcommander.JCommander;
import io.swagger.v3.oas.annotations.Parameter;
import javax.ws.rs.*;

// JCommander's own API is imported, but `Parameter` is swagger's.
@Path("/gadgets")
public class GadgetResource {
    @GET
    public void list(@QueryParam("mode") @Parameter(example = "x") String mode) {
        Gadget gadget = repo.find(mode);
        new JCommander(gadget);
    }
}
