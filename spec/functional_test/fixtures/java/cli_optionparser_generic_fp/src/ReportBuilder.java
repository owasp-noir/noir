import java.util.Map;

// No jopt library import anywhere in this file/project — `OptionParser`
// here is the app's own report-options parsing helper, unrelated to any
// third-party CLI parsing library. Must NOT be tagged as java_cli.
public class ReportBuilder {
    static class OptionParser {
        OptionParser(Map<String, String> settings) {
        }

        void process() {
        }
    }

    void build(Map<String, String> settings) {
        OptionParser parser = new OptionParser(settings);
        parser.process();
    }
}
