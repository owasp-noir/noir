import com.beust.jcommander.JCommander;
import com.beust.jcommander.Parameter;
import com.beust.jcommander.Parameters;

import java.util.ArrayList;
import java.util.List;

public class Tool {
    @Parameter(names = {"-v", "--verbose"}, description = "Verbose mode")
    private boolean verbose;

    @Parameter(description = "files")
    private List<String> files = new ArrayList<>();

    public static void main(String[] args) {
        Tool tool = new Tool();
        CommandServe serve = new CommandServe();
        JCommander jc = JCommander.newBuilder()
                .addObject(tool)
                .addCommand("serve", serve)
                .build();
        jc.parse(args);
        String token = System.getenv("JC_TOKEN");
        System.out.println(token);
    }
}

@Parameters(commandNames = "serve", commandDescription = "Start the server")
class CommandServe {
    @Parameter(names = "--port", description = "Port to listen on")
    private int port = 8080;
}
