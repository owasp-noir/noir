package io.helidon.examples.quickstart.mp;

public class GreetingMessage {

    private String message;

    public GreetingMessage() {
    }

    public GreetingMessage(String message) {
        this.message = message;
    }

    public String getMessage() {
        return message;
    }

    public void setMessage(String message) {
        this.message = message;
    }
}
