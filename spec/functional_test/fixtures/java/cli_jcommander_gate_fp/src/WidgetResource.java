import com.beust.jcommander.internal.Maps;
import io.swagger.v3.oas.annotations.Parameter;
import javax.ws.rs.*;

// `com.beust.jcommander.internal.Maps` is a collections helper that ships in
// the JCommander jar; importing it does not make this class a CLI. The
// name-less swagger `@Parameter` must not bind the next declaration as an
// "argument".
@Path("/widgets")
public class WidgetResource {
    @PUT
    @Path("/{id}/status")
    public void update(@PathParam("id") int id,
                       @QueryParam("mode") @Parameter(example = "x") String mode) {
        Widget widget = repo.find(id);
        widget.touch();
    }
}
