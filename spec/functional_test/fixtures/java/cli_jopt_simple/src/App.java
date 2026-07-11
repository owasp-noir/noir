import joptsimple.OptionParser;
import joptsimple.OptionSet;
import java.util.Arrays;

public class App {
    public static void main(String[] args) {
        OptionParser parser = new OptionParser();
        parser.accepts("verbose", "enable verbose output");
        parser.acceptsAll(Arrays.asList("h", "help"), "show help").forHelp();

        OptionSet options = parser.parse(args);
        String token = System.getenv("APP_TOKEN");
    }
}
