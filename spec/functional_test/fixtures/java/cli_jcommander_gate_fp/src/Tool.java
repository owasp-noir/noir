import com.beust.jcommander.JCommander;
import com.beust.jcommander.Parameter;

// The one genuine JCommander tool; it must keep its option.
public class Tool {
    @Parameter(names = {"-v", "--verbose"}, description = "Verbose mode")
    private boolean verbose;

    public static void main(String[] args) {
        Tool tool = new Tool();
        JCommander.newBuilder().addObject(tool).build().parse(args);
    }
}
