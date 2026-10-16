import org.apache.maven.plugins.annotations.Mojo;
import org.apache.maven.plugins.annotations.Parameter;
import org.apache.maven.project.MavenProject;

// A Maven plugin Mojo: its `@Parameter` fields are build configuration, not
// argv. It must not surface as a `cli://StopMojo` endpoint.
@Mojo(name = "stop")
public class StopMojo {
    @Parameter(defaultValue = "${project}", readonly = true, required = true)
    private MavenProject project;

    @Parameter(property = "spring-boot.stop.skip", defaultValue = "false")
    private boolean skip;
}
