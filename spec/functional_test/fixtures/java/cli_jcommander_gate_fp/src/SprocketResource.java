import com.beust.jcommander.*;
import io.swagger.v3.oas.annotations.Parameter;
import javax.ws.rs.*;

// A single-type import shadows the wildcard: `Parameter` is still swagger's.
@Path("/sprockets")
public class SprocketResource {
    @GET
    public void list(@QueryParam("mode") @Parameter(example = "x") String mode) {
        Sprocket sprocket = repo.find(mode);
    }
}
