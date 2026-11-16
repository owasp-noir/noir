import static spark.Spark.*;

class App {
    void setup() {
        String example = "staticFiles.location(\"/fake\")";
        String docs = """
            externalStaticFileLocation("/fake-text-block");
            """;
        // staticFileLocation("/comment");
        get("/real", (req, res) -> "ok");
    }
}
