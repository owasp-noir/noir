import joptsimple.OptionParser;
import joptsimple.OptionSet;

public class App {
    // Unrelated helper class that happens to also define an `accepts(...)`
    // method. Its receiver (`matcher`) is never bound to `new OptionParser(...)`,
    // so calls on it must NOT be attributed as a CLI flag.
    static class FormatMatcher {
        boolean accepts(String fmt) {
            return fmt.equals("csv");
        }
    }

    public static void main(String[] args) {
        OptionParser parser = new OptionParser();
        parser.accepts("topic", "the topic to publish");

        FormatMatcher matcher = new FormatMatcher();
        if (matcher.accepts("csv")) {
            System.out.println("csv format");
        }

        OptionSet options = parser.parse(args);
    }
}
