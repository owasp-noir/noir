import picocli.CommandLine;
import picocli.CommandLine.Command;
import picocli.CommandLine.Option;

// The one genuine CLI in the tree; it is what makes java_cli run at all.
@Command(name = "tool", description = "Real picocli tool")
public class Tool implements Runnable {
    @Option(names = {"-v", "--verbose"}, description = "Verbose mode")
    boolean verbose;

    public void run() {
    }

    public static void main(String[] args) {
        new CommandLine(new Tool()).execute(args);
    }
}
