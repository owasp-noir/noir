import picocli.CommandLine;
import picocli.CommandLine.Command;
import picocli.CommandLine.Option;
import picocli.CommandLine.Parameters;

@Command(name = "app", subcommands = {ServeCommand.class})
class App implements Runnable {
    @Option(names = {"-v", "--verbose"})
    boolean verbose;

    public void run() {
        String token = System.getenv("API_TOKEN");
    }
}

@Command(name = "serve")
class ServeCommand implements Runnable {
    @Option(names = {"-p", "--port"})
    int port;

    @Parameters(index = "0")
    String config;

    public void run() {
    }
}
