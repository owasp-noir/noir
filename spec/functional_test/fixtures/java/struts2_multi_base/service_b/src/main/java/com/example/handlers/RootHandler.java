package com.example.handlers;

public class RootHandler {
    private final RootService bService = new RootService();

    public String execute() {
        bService.load();
        return "success";
    }
}
