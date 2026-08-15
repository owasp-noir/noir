package io.helidon.examples.quickstart.se;

import io.helidon.http.HeaderNames;
import io.helidon.webserver.http.HttpRules;
import io.helidon.webserver.http.HttpService;
import io.helidon.webserver.http.ServerRequest;
import io.helidon.webserver.http.ServerResponse;

public class GreetService implements HttpService {

    @Override
    public void routing(HttpRules rules) {
        rules.get("/", this::getDefaultMessageHandler)
             .get("/{name}", this::getMessageHandler)
             .put("/greeting", this::updateGreetingHandler)
             .register("/admin", new AdminService());
    }

    private void getDefaultMessageHandler(ServerRequest request, ServerResponse response) {
        String lang = request.query().first("lang").orElse("en");
        response.send("Hello " + lang);
    }

    private void getMessageHandler(ServerRequest request, ServerResponse response) {
        String name = request.path().pathParameters().get("name");
        String trace = request.headers().get(HeaderNames.create("X-Trace-Id")).value();
        response.send(name + trace);
    }

    private void updateGreetingHandler(ServerRequest request, ServerResponse response) {
        GreetingUpdate update = request.content().as(GreetingUpdate.class);
        String session = request.headers().cookies().get("session");
        response.status(204).send();
    }

    static class GreetingUpdate {
        public String greeting;
    }
}
